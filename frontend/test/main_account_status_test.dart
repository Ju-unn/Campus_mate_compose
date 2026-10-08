import 'dart:convert';

import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/account/view/account_suspended_screen.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/model/fake_verification_gate_repository.dart';
import 'chat/model/fake_chat_repository.dart';
import 'core/draft/fake_draft_store.dart';
import 'core/push/fake_push_messaging.dart';
import 'home/model/fake_home_repository.dart';
import 'matching/model/fake_card_repository.dart';
import 'profile/model/fake_onboarding_repository.dart';

/// main.dart 의 계정 상태 배선 세 줄(조각 6 A4)을 지킨다 — 리스너(탈퇴 → 로그아웃),
/// 라우터 refresh 병합(정지 → 안내), apiClientProvider 의 onFailure(헤더 → 상태).
/// 줄 하나만 빠져도 다른 테스트는 모두 통과했다(pr6b 검토 권고 2).
void main() {
  // widget_test.dart 와 같은 더미 초기화 — CampusMateApp 이 Supabase 세션을 직접 읽는다.
  // 여기는 세션을 지우기도 해서(remove) 쓰기 호출에 성공(true)을 돌려준다.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        return <String, Object>{};
      }
      return true;
    });
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  tearDown(LoginNotice.take);

  testWidgets('탈퇴가 되면 로그아웃을 한 번만 부르고 로그인 화면 알림을 남긴다', (tester) async {
    var signOutCalls = 0;
    final container = ProviderContainer(overrides: [signOutProvider.overrideWithValue(() async => signOutCalls++)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));

    final status = container.read(accountStatusListenableProvider);
    status.markWithdrawn();
    // 다른 요청이 같은 401 을 또 받아도 로그아웃은 한 번이다.
    status.observe(const WithdrawnFailure());

    expect(signOutCalls, 1);
    expect(LoginNotice.take(), '탈퇴한 계정이에요');
  });

  group('로그인한 사용자', () {
    // group 본문은 setUpAll(초기화)보다 먼저 돈다 — 쓸 때 꺼낸다.
    GoTrueClient auth() => Supabase.instance.client.auth;

    // 토큰은 JWT 가 아니라 만료 시각을 못 읽는다 — gotrue 가 갱신하러 나가지 않는다.
    setUp(() => auth().setInitialSession(jsonEncode({
          'access_token': 'test-access-token',
          'token_type': 'bearer',
          'user': {'id': 'u1', 'aud': 'authenticated', 'created_at': '2026-09-28T00:00:00Z'},
        })));

    // 세션을 비운다. 서버 알림은 테스트 바인딩의 가짜 HTTP 가 400 으로 막는다 — 이 기기 세션은 이미 지워졌다.
    tearDown(() async {
      try {
        await auth().signOut();
      } on AuthException {
        // 위 주석.
      }
    });

    testWidgets('정지가 되면 보고 있던 화면에서 정지 안내로 간다', (tester) async {
      final container = ProviderContainer(
        overrides: [
          verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
          onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
          pushMessagingProvider.overrideWithValue(FakePushMessaging(token: 't', granted: false)),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          signOutProvider.overrideWithValue(() async {}),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
      // 스플래시(SplashHold 2초)를 지나 홈에 선다.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      // 다른 신호(세션 · 게이트 · 스플래시) 없이 계정 상태만 바뀐다 — 라우터가 이것을 들어야 한다.
      container.read(accountStatusListenableProvider).observe(const SuspendedFailure());
      await tester.pumpAndSettle();

      expect(find.byType(AccountSuspendedScreen), findsOneWidget);
    });

    testWidgets('세션이 스스로 끝나면(signedOut 만 온다) 온보딩 임시 저장 값을 지운다', (tester) async {
      // gotrue 가 토큰 갱신에 실패해 세션을 스스로 버리면 signOut() 을 지나지 않는다 — 그래도 폰에 값을 남기지 않는다.
      final drafts = FakeDraftStore(accountId: 'u1')..saved['u1/basic_info'] = '{"nickname":"가나다"}';
      final container = ProviderContainer(
        overrides: [
          verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
          onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
          pushMessagingProvider.overrideWithValue(FakePushMessaging(token: 't', granted: false)),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          signOutProvider.overrideWithValue(() async {}),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(drafts.clearAllCalls, 0, reason: '로그인한 채로 켜면 지우지 않는다');

      // 앱의 로그아웃(signOutProvider)을 거치지 않고 세션만 사라진다.
      await tester.runAsync(() async {
        try {
          await auth().signOut();
        } on AuthException {
          // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
        }
      });
      await tester.pumpAndSettle();

      expect(drafts.clearAllCalls, greaterThanOrEqualTo(1));
      expect(drafts.saved, isEmpty);
    });

    test('앱 공용 ApiClient 가 탈퇴 헤더를 받으면 계정 상태가 탈퇴가 된다', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // provider 안의 `http.Client()` 가 이 가짜를 받는다(http 의 runWithClient).
      final api = http.runWithClient(
        () => container.read(apiClientProvider),
        () => MockClient((_) async => http.Response('', 401, headers: {'x-account-status': 'withdrawn'})),
      );

      await api.send('GET', '/me', (_) {});

      expect(container.read(accountStatusListenableProvider).value, AccountStatus.withdrawn);
    });
  });
}
