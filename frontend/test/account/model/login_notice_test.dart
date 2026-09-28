import 'dart:convert';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/account/viewmodel/withdraw_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_account_repository.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  // LoginNotice 는 전역 값이다 — 테스트끼리 값이 새지 않게 매번 비운다(대장 요구).
  tearDown(LoginNotice.take);

  test('LoginNotice.take returns the posted message once, then null', () {
    LoginNotice.post('탈퇴한 계정이에요');

    expect(LoginNotice.take(), '탈퇴한 계정이에요');
    expect(LoginNotice.take(), isNull);
  });

  test('signOutWhenWithdrawn 은 withdrawn 이 아니면 아무것도 하지 않는다', () async {
    var signOutCalls = 0;
    for (final status in [AccountStatus.active, AccountStatus.suspended]) {
      signOutWhenWithdrawn(status, () async => signOutCalls++);
    }

    expect(LoginNotice.take(), isNull);
    expect(signOutCalls, 0);
  });

  // 두 경로(대장 요구 2026-09-28). main.dart 처럼 listenable 에 리스너로 signOutWhenWithdrawn 을 건다.
  group('탈퇴 토스트의 두 경로', () {
    late ProviderContainer container;
    late AccountStatusListenable listenable;
    late int signOutCalls;
    late MockGoTrueClient auth;

    /// 탈퇴 ViewModel 이 읽을 저장소. 테스트마다 바꿔 끼운다(처음 읽힐 때 정해진다).
    late AccountRepository repository;

    setUp(() {
      signOutCalls = 0;
      auth = MockGoTrueClient();
      final session = MockSession();
      when(() => session.accessToken).thenReturn('token-abc');
      when(() => auth.currentSession).thenReturn(session);
      repository = FakeAccountRepository();
      container = ProviderContainer(
        overrides: [accountRepositoryProvider.overrideWith((ref) => repository)],
      );
      listenable = container.read(accountStatusListenableProvider);
      listenable.addListener(() => signOutWhenWithdrawn(listenable.value, () async => signOutCalls++));
      // 16c 최종 시트가 떠 있는 동안처럼 붙잡아 둔다(autoDispose).
      container.listen(withdrawViewModelProvider, (_, _) {});
    });

    tearDown(() => container.dispose());

    /// 앱의 apiClientProvider 와 같은 배선 — 실패를 listenable 에 올린다.
    ApiClient apiReturning(http.Response Function() respond) {
      return ApiClient(
        'https://api.test',
        MockClient((request) async => respond()),
        auth,
        onFailure: listenable.observe,
      );
    }

    http.Response rejected(int status, String detail, String? accountStatus) {
      return http.Response(
        jsonEncode({'detail': detail}),
        status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'x-account-status': ?accountStatus,
        },
      );
    }

    test('direct withdraw: WithdrawViewModel success → notice posted and signOut once', () async {
      await container.read(withdrawViewModelProvider.notifier).withdraw();

      expect(LoginNotice.take(), '탈퇴한 계정이에요');
      expect(signOutCalls, 1);
    });

    test('direct withdraw 재시도: 401 + withdrawn 이 ApiClient 와 ViewModel 양쪽에 와도 signOut 은 한 번', () async {
      // 실제 배선 그대로 — ApiClient 가 먼저 observe 하고, ViewModel 이 성공으로 보고 markWithdrawn 한다.
      repository = HttpAccountRepository(apiReturning(() => rejected(401, '탈퇴한 계정이에요', 'withdrawn')));

      await container.read(withdrawViewModelProvider.notifier).withdraw();

      expect(container.read(withdrawViewModelProvider).errorMessage, isNull);
      expect(LoginNotice.take(), '탈퇴한 계정이에요');
      expect(signOutCalls, 1);
    });

    test('other device: ApiClient 401 + X-Account-Status withdrawn → notice posted and signOut once', () async {
      final api = apiReturning(() => rejected(401, '탈퇴한 계정이에요', 'withdrawn'));

      // 화면 여럿이 동시에 부른 요청이 한꺼번에 401 로 돌아온다.
      await Future.wait([
        api.send('GET', '/home/summary', (_) {}),
        api.send('GET', '/cards/today', (_) {}),
      ]);

      expect(LoginNotice.take(), '탈퇴한 계정이에요');
      expect(signOutCalls, 1);
    });

    test('suspended or other failures post nothing and do not sign out', () async {
      // 16c 에서 네트워크 실패 — 탈퇴하지 못했으니 로그아웃도 없다.
      (repository as FakeAccountRepository).withdrawResult = const FailureResult(NetworkFailure());
      await container.read(withdrawViewModelProvider.notifier).withdraw();
      await apiReturning(() => rejected(403, '이용이 제한된 계정이에요', 'suspended')).send('GET', '/a', (_) {});
      await apiReturning(() => rejected(401, '세션이 만료됐어요, 다시 로그인해 주세요', null)).send('GET', '/b', (_) {});
      await apiReturning(() => http.Response('', 500)).send('GET', '/c', (_) {});

      expect(listenable.value, AccountStatus.suspended);
      expect(LoginNotice.take(), isNull);
      expect(signOutCalls, 0);
    });
  });
}
