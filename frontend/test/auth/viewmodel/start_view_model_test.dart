import 'dart:async';

import 'package:campus_mate/auth/model/social_login_repository_provider.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/viewmodel/start_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/start_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_social_login_repository.dart';

void main() {
  late FakeSocialLoginRepository repository;
  late ProviderContainer container;

  StartUiState state() => container.read(startViewModelProvider);
  StartViewModel viewModel() => container.read(startViewModelProvider.notifier);

  setUp(() {
    repository = FakeSocialLoginRepository();
    container = ProviderContainer(overrides: [socialLoginRepositoryProvider.overrideWithValue(repository)]);
  });

  tearDown(() => container.dispose());

  test('처음에는 진행 중인 로그인도 토스트도 없다', () {
    expect(state().inProgress, isNull);
    expect(state().toast, isNull);
    expect(state().isEnabled(SocialProvider.kakao), isTrue);
  });

  test('누르면 그 공급자가 진행 중이 되고 나머지 버튼은 비활성이다', () {
    viewModel().signIn(SocialProvider.kakao);

    expect(state().isLoading(SocialProvider.kakao), isTrue);
    expect(state().isLoading(SocialProvider.google), isFalse);
    expect(state().isEnabled(SocialProvider.google), isFalse);
    expect(state().isEnabled(SocialProvider.kakao), isFalse);
  });

  test('진행 중에 다시 누르면(같은 버튼이든 다른 버튼이든) 무시한다', () {
    viewModel().signIn(SocialProvider.kakao);
    viewModel().signIn(SocialProvider.kakao);
    viewModel().signIn(SocialProvider.google);

    expect(repository.requested, [SocialProvider.kakao]);
  });

  test('성공하면 진행 표시를 거두고 토스트를 띄우지 않는다 — 화면 이동은 세션 리스너 → 라우터가 한다', () async {
    final signIn = viewModel().signIn(SocialProvider.google);
    repository.completer.complete(const Success(null));
    await signIn;

    expect(state().inProgress, isNull);
    expect(state().toast, isNull);
  });

  test('취소면 아이콘 없는 취소 토스트', () async {
    final signIn = viewModel().signIn(SocialProvider.kakao);
    repository.completer.complete(const FailureResult(LoginCancelledFailure()));
    await signIn;

    expect(state().inProgress, isNull);
    expect(state().toast?.message, '로그인이 취소됐어요');
    expect(state().toast?.hasWarningIcon, isFalse);
  });

  test('실패면 경고 아이콘이 있는 실패 토스트', () async {
    final signIn = viewModel().signIn(SocialProvider.kakao);
    repository.completer.complete(const FailureResult(SocialLoginFailure()));
    await signIn;

    expect(state().toast?.message, '로그인하지 못했어요. 잠시 뒤 다시 시도해 주세요');
    expect(state().toast?.hasWarningIcon, isTrue);
  });

  test('토스트를 닫으면 사라지고, 다시 누를 수 있다', () async {
    final signIn = viewModel().signIn(SocialProvider.kakao);
    repository.completer.complete(const FailureResult(SocialLoginFailure()));
    await signIn;

    viewModel().dismissToast();

    expect(state().toast, isNull);
    expect(state().isEnabled(SocialProvider.kakao), isTrue);
  });

  test('새로 누르면 앞 토스트는 지운다', () async {
    final signIn = viewModel().signIn(SocialProvider.kakao);
    repository.completer.complete(const FailureResult(SocialLoginFailure()));
    await signIn;
    repository.completer = Completer();

    viewModel().signIn(SocialProvider.google);

    expect(state().toast, isNull);
  });

  test('로그아웃 알림(탈퇴 등)도 같은 토스트 자리에 경고 아이콘과 함께 띄운다', () {
    viewModel().showNotice('탈퇴한 계정이에요');

    expect(state().toast?.message, '탈퇴한 계정이에요');
    expect(state().toast?.hasWarningIcon, isTrue);
  });
}
