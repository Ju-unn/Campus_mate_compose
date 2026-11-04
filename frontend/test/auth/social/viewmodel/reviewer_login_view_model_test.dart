import 'package:campus_mate/auth/social/model/repository/social_login_repository_provider.dart';
import 'package:campus_mate/auth/social/viewmodel/reviewer_login_ui_state.dart';
import 'package:campus_mate/auth/social/viewmodel/reviewer_login_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/analytics/fake_analytics_service.dart';
import '../model/repository/fake_social_login_repository.dart';

// 이 파일의 이메일 · 비밀번호는 모두 가짜다.
const _email = 'reviewer@example.test';
const _password = 'fake-password-1';

void main() {
  late FakeSocialLoginRepository repository;
  late FakeAnalyticsService analytics;
  late ProviderContainer container;

  ReviewerLoginUiState state() => container.read(reviewerLoginViewModelProvider);
  ReviewerLoginViewModel viewModel() => container.read(reviewerLoginViewModelProvider.notifier);

  setUp(() {
    repository = FakeSocialLoginRepository();
    analytics = FakeAnalyticsService();
    container = ProviderContainer(overrides: [
      socialLoginRepositoryProvider.overrideWithValue(repository),
      analyticsServiceProvider.overrideWithValue(analytics),
    ]);
    addTearDown(container.dispose);
    // 시트가 떠 있는 동안처럼 붙잡아 둔다(autoDispose).
    container.listen(reviewerLoginViewModelProvider, (_, _) {});
  });

  test('처음에는 진행 중도 실패도 닫힘 신호도 없다', () {
    expect((state().isSubmitting, state().failure, state().completed), (false, null, false));
  });

  group('빈 칸 제출 막기', () {
    test('이메일이 비었으면 저장소를 부르지 않는다', () async {
      await viewModel().signIn('', _password);

      expect(repository.passwordRequests, isEmpty);
      expect(state().isSubmitting, isFalse);
    });

    test('이메일이 공백뿐이어도 부르지 않는다', () async {
      await viewModel().signIn('   ', _password);

      expect(repository.passwordRequests, isEmpty);
    });

    test('비밀번호가 비었으면 부르지 않는다', () async {
      await viewModel().signIn(_email, '');

      expect(repository.passwordRequests, isEmpty);
      expect(state().isSubmitting, isFalse);
    });
  });

  group('진행 중', () {
    test('누르면 진행 중이 되고, 진행 중에 다시 눌러도 저장소는 한 번만 부른다', () async {
      final first = viewModel().signIn(_email, _password);
      await viewModel().signIn(_email, _password);
      await viewModel().signIn('other@example.test', 'other-password');

      expect(state().isSubmitting, isTrue);
      expect(repository.passwordRequests, [(_email, _password)]);
      repository.passwordCompleter.complete(const Success(null));
      await first;
    });

    test('이메일 앞뒤 공백은 지우고 보내고, 비밀번호는 한 글자도 바꾸지 않는다', () async {
      repository.nextPasswordResult = const Success(null);

      await viewModel().signIn('  $_email \n', ' $_password ');

      expect(repository.passwordRequests, [(_email, ' $_password ')]);
    });
  });

  group('성공', () {
    test('진행 표시를 거두고 닫힘 신호를 올린다 — 이동은 세션 리스너 → 게이트 → 라우터가 한다', () async {
      final signIn = viewModel().signIn(_email, _password);
      repository.passwordCompleter.complete(const Success(null));
      await signIn;

      expect((state().isSubmitting, state().failure, state().completed), (false, null, true));
    });

    test('사용 통계 login 이벤트를 남기지 않는다(심사원 로그인이 통계에 섞이지 않는다)', () async {
      repository.nextPasswordResult = const Success(null);

      await viewModel().signIn(_email, _password);

      expect(analytics.calls, isEmpty);
    });
  });

  group('실패', () {
    test('잘못된 자격이면 실패 종류를 상태에 담고 닫지 않는다 — 다시 시도할 수 있다', () async {
      repository.nextPasswordResult = const FailureResult(SocialLoginFailure());

      await viewModel().signIn(_email, _password);

      expect(state().failure, isA<SocialLoginFailure>());
      expect((state().isSubmitting, state().completed), (false, false));
    });

    test('한도에 걸리면(429) RateLimitedFailure 를 그대로 담는다', () async {
      repository.nextPasswordResult = const FailureResult(RateLimitedFailure());

      await viewModel().signIn(_email, _password);

      expect(state().failure, isA<RateLimitedFailure>());
    });

    test('실패 뒤 다시 누르면 실패 표시를 지우고 진행 중이 된다', () async {
      repository.nextPasswordResult = const FailureResult(SocialLoginFailure());
      await viewModel().signIn(_email, _password);
      repository.nextPasswordResult = null;

      final retry = viewModel().signIn(_email, _password);

      expect((state().isSubmitting, state().failure), (true, null));
      repository.passwordCompleter.complete(const Success(null));
      await retry;
      expect(repository.passwordRequests.length, 2);
    });

    test('실패해도 분석에는 아무것도 남기지 않는다', () async {
      repository.nextPasswordResult = const FailureResult(SocialLoginFailure());

      await viewModel().signIn(_email, _password);

      expect(analytics.calls, isEmpty);
    });
  });

  test('로그인 요청 도중 시트가 닫혀도(상태가 버려져도) 응답이 와서 오류가 나지 않는다', () async {
    final scoped = ProviderContainer(overrides: [socialLoginRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(scoped.dispose);
    final subscription = scoped.listen(reviewerLoginViewModelProvider, (_, _) {});
    final signIn = scoped.read(reviewerLoginViewModelProvider.notifier).signIn(_email, _password);

    subscription.close();
    await scoped.pump();
    repository.passwordCompleter.complete(const Success(null));

    await expectLater(signIn, completes);
  });
}
