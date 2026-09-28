import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/me/viewmodel/profile_edit_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_me_repository.dart';

const _profile = MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: null,
  heightCm: null,
  mbti: null,
  avatarUrl: null,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: null,
  preferredHeightMax: null,
  bio: '주말엔 산책해요.',
);

void main() {
  late FakeMeRepository me;
  late ProviderContainer container;
  late ProviderSubscription<ProfileEditUiState> subscription;

  ProfileEditViewModel viewModel() => container.read(profileEditViewModelProvider.notifier);

  setUp(() async {
    me = FakeMeRepository(const Success(_profile));
    container = ProviderContainer(overrides: [meRepositoryProvider.overrideWithValue(me)]);
    // 15c 는 화면 15 를 거쳐 열린다 — 그때는 내 프로필이 이미 읽혀 있다.
    await container.read(myProfileProvider.future);
    subscription = container.listen(profileEditViewModelProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  test('열면 서버의 자기소개로 채워진다', () {
    expect(subscription.read().bio, '주말엔 산책해요.');
    expect(subscription.read().canSave, isTrue);
  });

  for (final blank in ['', '   ', '\n']) {
    test('자기소개가 비면("$blank") 저장할 수 없다 — 06-3 과 같은 규칙', () {
      viewModel().changeBio(blank);

      expect(subscription.read().canSave, isFalse);
    });
  }

  test('저장하면 앞뒤 공백을 뗀 자기소개만 PATCH 하고 화면 15 값을 다시 읽는다', () async {
    viewModel().changeBio('  새 소개예요.  ');

    await viewModel().save();
    await container.read(myProfileProvider.future);

    expect(me.updates, [
      {'bio': '새 소개예요.'},
    ]);
    expect(subscription.read().completed, isTrue);
    expect(me.calls, 2, reason: '저장 뒤 invalidate 로 GET /me/profile 을 한 번 더 부른다');
  });

  test('저장하는 동안은 isSubmitting 이고 다시 누를 수 없다', () async {
    me.holdUpdate = Completer<void>();

    final saving = viewModel().save();

    expect(subscription.read().isSubmitting, isTrue);
    expect(subscription.read().canSave, isFalse);
    await viewModel().save();
    expect(me.updates, hasLength(1));
    me.holdUpdate!.complete();
    await saving;
    expect(subscription.read().isSubmitting, isFalse);
  });

  test('저장이 실패하면 문구를 보이고 끝나지 않는다 — 화면 15 값도 다시 읽지 않는다', () async {
    me.updateResult = const FailureResult(NetworkFailure());

    await viewModel().save();

    expect(subscription.read().completed, isFalse);
    expect(subscription.read().isSubmitting, isFalse);
    expect(subscription.read().errorMessage, const NetworkFailure().toDisplayMessage());
    expect(me.calls, 1);
  });

  test('저장 중에 화면을 떠나도(autoDispose) 끝난 저장이 오류를 내지 않고 화면 15 는 다시 읽힌다', () async {
    me.holdUpdate = Completer<void>();
    final saving = viewModel().save();

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    me.holdUpdate!.complete();
    await saving;
    await container.read(myProfileProvider.future);

    expect(me.updates, hasLength(1));
    expect(me.calls, 2);
    subscription = container.listen(profileEditViewModelProvider, (_, _) {});
  });

  test('profile_edit_is_filled_from_the_server_each_time_it_opens — 고치다 만 글은 닫으면 사라진다(Review Focus 5)', () async {
    viewModel().changeBio('고치다 만 글');

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    subscription = container.listen(profileEditViewModelProvider, (_, _) {});

    expect(subscription.read().bio, '주말엔 산책해요.');
  });
}
