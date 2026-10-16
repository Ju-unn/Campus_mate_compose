import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/acceptance_detail_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptance_detail_view_model.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

final _detail = CardDetail(
  cardId: 'card-1',
  profile: const CardProfile(profileId: 'p1', nickname: '초코라떼', age: 25, avatarUrl: 'https://img.test/a.png'),
  survey: List.filled(9, 0.0),
  animalType: AnimalType.cat,
  impressionType: ImpressionType.chic,
  religion: Religion.none,
  isSmoker: false,
  interests: const [],
  myTraits: const [],
  idealTraits: const [],
);

/// 받은 신청 · 프로필 보기(pen `o4QqYR`)의 읽기. 결정(거절 · 수락)은 받은 신청 목록 뷰모델의 respond 를 그대로 쓴다.
void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository()..acceptanceDetail = Success(_detail);
    container = ProviderContainer(overrides: [cardRepositoryProvider.overrideWithValue(repository)]);
  });

  tearDown(() => container.dispose());

  /// 화면이 붙어 있는 동안처럼 구독해 두고 첫 읽기가 끝날 때까지 기다린다.
  Future<ProviderSubscription<AcceptanceDetailUiState>> open(String cardId) async {
    final subscription = container.listen(acceptanceDetailViewModelProvider(cardId), (_, _) {});
    await pumpEventQueue();
    return subscription;
  }

  test('처음엔 읽는 중이고, 그 카드 번호로 서버 몸통을 읽어 상태에 담는다', () async {
    final subscription = container.listen(acceptanceDetailViewModelProvider('card-1'), (_, _) {});
    expect(subscription.read().isLoading, isTrue);

    await pumpEventQueue();

    final state = subscription.read();
    expect(repository.acceptanceDetailReads, ['card-1']);
    expect(state.isLoading, isFalse);
    expect(state.detail!.profile.nickname, '초코라떼');
    expect(state.errorMessage, isNull);
  });

  test('만료(410) · 이미 답함(409) · 없음(404)은 서버 문구 그대로 오류 상태다', () async {
    repository.acceptanceDetail = const FailureResult(ServerRejectedFailure('기한이 지났어요'));

    final state = (await open('card-1')).read();

    expect(state.isLoading, isFalse);
    expect(state.detail, isNull);
    expect(state.errorMessage, '기한이 지났어요');
  });

  test('화면을 떠나면 버리고, 다시 열면 새로 읽는다 — 그사이 상대가 사라졌거나 기한이 지났을 수 있다', () async {
    final first = await open('card-1');
    first.close();
    await pumpEventQueue();

    await open('card-1');

    expect(repository.acceptanceDetailReads, ['card-1', 'card-1']);
  });

  test('카드마다 상태가 따로 산다', () async {
    repository.acceptanceDetail = Success(_detail);
    await open('card-1');
    await open('card-2');

    expect(repository.acceptanceDetailReads, ['card-1', 'card-2']);
  });
}
