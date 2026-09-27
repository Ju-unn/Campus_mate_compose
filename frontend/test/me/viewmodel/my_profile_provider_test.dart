import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_me_repository.dart';

void main() {
  const profile = MyProfile(
    nickname: '여우',
    age: 23,
    university: '가나대학교',
    major: '경영학과',
    heightCm: 178,
    mbti: null,
    avatarUrl: null,
    photoUrls: [],
    preferredAgeMin: 22,
    preferredAgeMax: 27,
    preferredHeightMin: null,
    preferredHeightMax: null,
    bio: '안녕하세요',
  );

  ProviderContainer containerWith(Result<MyProfile> result) {
    final container = ProviderContainer(
      overrides: [meRepositoryProvider.overrideWithValue(FakeMeRepository(result))],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('받으면 성공 결과를 그대로 준다', () async {
    final result = await containerWith(const Success(profile)).read(myProfileProvider.future);

    expect(result.when(onSuccess: (p) => p, onFailure: (_) => null), same(profile));
  });

  test('못 받으면 던지지 않고 실패 결과를 준다 — 화면이 실패 상태를 그린다', () async {
    final container = containerWith(const FailureResult(NetworkFailure()));

    final result = await container.read(myProfileProvider.future);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
    expect(container.read(myProfileProvider).hasError, isFalse);
  });
}
