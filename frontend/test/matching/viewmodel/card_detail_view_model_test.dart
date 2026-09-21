import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/card_detail_view_model.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository()..card = Success(_detail);
    container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
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
