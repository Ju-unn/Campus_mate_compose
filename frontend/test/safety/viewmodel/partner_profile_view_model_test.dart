import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/viewmodel/partner_profile_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/partner_profile_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_safety_repository.dart';

void main() {
  late FakeSafetyRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeSafetyRepository();
    container = ProviderContainer(
      overrides: [safetyRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  Future<PartnerProfileUiState> opened([String profileId = 'p2']) async {
    container.listen(partnerProfileViewModelProvider(profileId), (_, _) {});
    // build() 의 microtask 가 끝나야 프로필이 들어온다.
    await Future<void>.delayed(Duration.zero);
    return container.read(partnerProfileViewModelProvider(profileId));
  }

  test('열자마자는 읽는 중이다', () {
    final initial = container.read(partnerProfileViewModelProvider('p2'));

    expect(initial.isLoading, isTrue);
    expect(initial.profile, isNull);
    expect(initial.isGone, isFalse);
  });

  test('열면 그 사람 프로필을 읽는다', () async {
    repository.partnerProfile = Success(partnerProfileFixture(nickname: '소나기'));

    final loaded = await opened('p3');

    expect(repository.partnerProfileRequests, ['p3']);
    expect(loaded.isLoading, isFalse);
    expect(loaded.profile!.detail.profile.nickname, '소나기');
    expect(loaded.errorMessage, isNull);
    expect(loaded.isGone, isFalse);
  });

  test('404 면 보여 줄 상대가 없다고 알리고, 나가며 짧게 띄울 서버 문구를 같이 넘긴다', () async {
    repository.partnerProfile = const FailureResult(ServerRejectedFailure('프로필을 찾을 수 없어요'));

    final loaded = await opened();

    expect(loaded.isLoading, isFalse);
    expect(loaded.isGone, isTrue);
    expect(loaded.profile, isNull);
    expect(loaded.errorMessage, '프로필을 찾을 수 없어요');
  });

  test('그 밖의 실패는 문구를 띄우고 화면에 남는다', () async {
    repository.partnerProfile = const FailureResult(NetworkFailure());

    final loaded = await opened();

    expect(loaded.isLoading, isFalse);
    expect(loaded.isGone, isFalse);
    expect(loaded.errorMessage, '네트워크 연결을 확인해 주세요');
  });

  test('읽는 중에 화면을 떠나도 응답이 왔을 때 터지지 않는다', () async {
    repository.holdPartnerProfile = Completer<void>();
    final subscription = container.listen(partnerProfileViewModelProvider('p2'), (_, _) {});
    await Future<void>.delayed(Duration.zero);

    // 14c 를 뒤로가기로 닫았다 — 보던 쪽이 없어져 autoDispose 가 버린다.
    subscription.close();
    await Future<void>.delayed(Duration.zero);
    repository.holdPartnerProfile!.complete();

    await Future<void>.delayed(Duration.zero);
  });
}
