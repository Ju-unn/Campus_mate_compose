import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/matching/model/card_decision.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/viewmodel/card_detail_view_model.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/analytics/fake_analytics_service.dart';
import '../model/fake_card_repository.dart';

final _detail = CardDetail(
  cardId: 'card-1',
  profile: const CardProfile(profileId: 't1', nickname: '여우비', age: 23),
  survey: List.filled(9, 0.5),
  animalType: AnimalType.cat,
  impressionType: ImpressionType.chic,
  religion: Religion.none,
  isSmoker: false,
  interests: const ['등산'],
  myTraits: const ['유머러스'],
  idealTraits: const ['다정한'],
);

void main() {
  late FakeCardRepository repository;
  late FakeAnalyticsService analytics;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository()..card = Success(_detail);
    analytics = FakeAnalyticsService();
    container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('상세를 읽어 상태에 담는다', () async {
    await container.read(cardDetailViewModelProvider('card-1').notifier).load();

    final state = container.read(cardDetailViewModelProvider('card-1'));
    expect(state.detail!.profile.nickname, '여우비');
    expect(state.survey.length, 9);
  });

  test('수락하면 수락으로 보내고 결정 완료 상태가 된다', () async {
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await viewModel.decide(CardDecision.accept);

    expect(repository.decisions.single.decision, CardDecision.accept);
    expect(container.read(cardDetailViewModelProvider('card-1')).decided, isTrue);
  });

  // 사용 통계 chat_request_sent 이벤트 — 서버가 수락(대화 신청)을 받아 준 뒤에만, 이름만 남긴다.
  test('수락이 서버에 받아들여지면 대화 신청을 분석에 남긴다', () async {
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await viewModel.decide(CardDecision.accept);

    expect(analytics.calls, ['chat_request_sent']);
  });

  test('거절은 대화 신청이 아니라 분석에 남기지 않는다', () async {
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await viewModel.decide(CardDecision.reject);

    expect(analytics.calls, isEmpty);
  });

  // 사용 통계 card_pass — 상세에서 "넘기기"(거절)를 서버가 받아 준 뒤에만, 카드 출처(free · purchased)만 남긴다.
  // 상세는 카드 id 만 알아서 출처는 오늘 탭이 읽어 둔 목록에서 찾는다.
  group('card_pass', () {
    Future<CardDetailViewModel> detailOf(CardSource source) async {
      repository.today = Success(
        TodayCards(cards: [DailyCard(cardId: 'card-1', source: source, profile: _detail.profile)]),
      );
      await container.read(todayCardsViewModelProvider.notifier).refresh();
      final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
      await viewModel.load();
      return viewModel;
    }

    test('무료 카드를 넘기면 free', () async {
      final viewModel = await detailOf(CardSource.daily);

      await viewModel.decide(CardDecision.reject);

      expect(analytics.calls, ['card_pass:free']);
    });

    test('산 카드를 넘기면 purchased', () async {
      final viewModel = await detailOf(CardSource.purchased);

      await viewModel.decide(CardDecision.reject);

      expect(analytics.calls, ['card_pass:purchased']);
    });

    test('수락은 넘기기가 아니다', () async {
      final viewModel = await detailOf(CardSource.daily);

      await viewModel.decide(CardDecision.accept);

      expect(analytics.calls, ['chat_request_sent']);
    });

    test('서버가 거절을 받아 주지 않으면(409) 남기지 않는다', () async {
      final viewModel = await detailOf(CardSource.daily);
      repository.writeResult = const FailureResult(ServerRejectedFailure('이미 결정한 카드예요'));

      await viewModel.decide(CardDecision.reject);

      expect(analytics.calls, isEmpty);
    });

    test('오늘 목록에서 출처를 못 찾으면 지어내지 않고 남기지 않는다', () async {
      final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
      await viewModel.load();

      await viewModel.decide(CardDecision.reject);

      expect(analytics.calls, isEmpty);
    });
  });

  test('서버가 수락을 막으면(409) 대화 신청을 분석에 남기지 않는다', () async {
    repository.writeResult = const FailureResult(ServerRejectedFailure('이미 결정한 카드예요'));
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await viewModel.decide(CardDecision.accept);

    expect(analytics.calls, isEmpty);
  });

  test('이미 결정한 카드(409)는 서버 문구를 그대로 보여준다', () async {
    repository.writeResult = const FailureResult(ServerRejectedFailure('이미 결정한 카드예요'));
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await viewModel.decide(CardDecision.reject);

    expect(
      container.read(cardDetailViewModelProvider('card-1')).errorMessage,
      '이미 결정한 카드예요',
    );
    expect(container.read(cardDetailViewModelProvider('card-1')).decided, isFalse);
  });

  test('보내는 동안에는 두 번 눌러도 한 번만 간다', () async {
    final viewModel = container.read(cardDetailViewModelProvider('card-1').notifier);
    await viewModel.load();

    await Future.wait([viewModel.decide(CardDecision.accept), viewModel.decide(CardDecision.accept)]);

    expect(repository.decisions.length, 1);
  });
}
