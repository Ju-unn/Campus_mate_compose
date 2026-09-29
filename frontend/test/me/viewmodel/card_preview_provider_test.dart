import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/viewmodel/card_preview_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_me_repository.dart';

void main() {
  const detail = CardDetail(
    cardId: 'me-1',
    profile: CardProfile(profileId: 'me-1', nickname: '하늘', age: 24),
    survey: [],
    animalType: AnimalType.fox,
    impressionType: ImpressionType.kind,
    religion: Religion.none,
    isSmoker: false,
    interests: [],
    myTraits: [],
    idealTraits: [],
  );

  (ProviderContainer, FakeMeRepository) containerWith(Result<CardDetail> result) {
    final repository = FakeMeRepository(const FailureResult(UnknownFailure()))..cardPreview = result;
    final container = ProviderContainer(overrides: [meRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    return (container, repository);
  }

  test('받으면 성공 결과를 그대로 준다', () async {
    final (container, _) = containerWith(const Success(detail));

    final result = await container.read(myCardPreviewProvider.future);

    expect(result.when(onSuccess: (d) => d, onFailure: (_) => null), same(detail));
  });

  test('못 받으면 던지지 않고 실패 결과를 준다 — 화면이 실패 상태를 그린다', () async {
    final (container, _) = containerWith(const FailureResult(NetworkFailure()));

    final result = await container.read(myCardPreviewProvider.future);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
    expect(container.read(myCardPreviewProvider).hasError, isFalse);
  });

  test('15-4 를 닫았다 다시 열면 새로 읽는다 — 15-5 에서 고친 값이 보인다', () async {
    final (container, repository) = containerWith(const Success(detail));

    final first = container.listen(myCardPreviewProvider, (_, _) {});
    await container.read(myCardPreviewProvider.future);
    first.close();
    // autoDispose 는 구독이 끊긴 뒤 다음 틱에 치운다.
    await Future<void>.delayed(Duration.zero);
    final second = container.listen(myCardPreviewProvider, (_, _) {});
    await container.read(myCardPreviewProvider.future);
    second.close();

    expect(repository.cardPreviewCalls, 2);
  });
}
