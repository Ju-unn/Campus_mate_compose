import 'dart:convert';

import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository_provider.dart';
import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/offline/offline_screen.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/home/model/repository/home_repository_provider.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/notifications/model/repository/notifications_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/gate/model/repository/fake_verification_gate_repository.dart';
import 'chat/model/repository/fake_chat_repository.dart';
import 'core/push/fake_push_messaging.dart';
import 'home/model/repository/fake_home_repository.dart';
import 'matching/model/repository/fake_card_repository.dart';
import 'notifications/model/repository/fake_notifications_repository.dart';
import 'profile/onboarding/model/repository/fake_onboarding_repository.dart';

/// main.dart 의 라우터 배선 `isOnboardingUnreachable` 한 줄을 지킨다(출시뒤_고칠것 11-13 3절).
/// 라우터 · 리스너블 시험은 각각 따로 통과해서, 앱 루트에서 이 줄이 빠지면 가입 단계 조회 실패가
/// 01-1 이 아니라 스플래시에 갇혀도 아무 시험도 잡지 못했다.
void main() {
  // main_account_status_test.dart 와 같은 더미 초기화 — CampusMateApp 이 Supabase 세션을 직접 읽는다.
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

  // group 본문은 setUpAll(초기화)보다 먼저 돈다 — 쓸 때 꺼낸다.
  GoTrueClient auth() => Supabase.instance.client.auth;

  // 토큰은 JWT 가 아니라 만료 시각을 못 읽는다 — gotrue 가 갱신하러 나가지 않는다.
  setUp(() => auth().setInitialSession(jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'user': {'id': 'u1', 'aud': 'authenticated', 'created_at': '2026-09-28T00:00:00Z'},
      })));

  // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 400 으로 막는다 — 이 기기 세션은 이미 지워졌다.
  tearDown(() async {
    try {
      await auth().signOut();
    } on AuthException {
      // 위 주석.
    }
  });

  /// 관문은 통과, 가입 단계 조회는 [onboarding] 이 정한다.
  ProviderContainer appContainer(FakeOnboardingRepository onboarding) {
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        pushMessagingProvider.overrideWithValue(FakePushMessaging(token: 't', granted: false)),
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        // 관문이 열리면 앱이 사용자 채널을 연다 — 시험에서는 진짜 Realtime 소켓을 열지 않는다.
        userEventStreamProvider.overrideWithValue(FakeUserEventStream()),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        signOutProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 앱을 켜고 스플래시(SplashHold 2초)를 지난다.
  Future<void> launch(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('앱을 켤 때 가입 단계 조회가 실패하면 01-1(다시 시도)에 선다', (tester) async {
    final onboarding = FakeOnboardingRepository()..nextResult = const FailureResult(NetworkFailure());
    await launch(tester, appContainer(onboarding));

    expect(find.byType(OfflineScreen), findsOneWidget);
  });

  testWidgets('01-1 에서 다시 시도해 단계를 알아내면 그 화면(가입 끝 → 홈)으로 간다', (tester) async {
    final onboarding = FakeOnboardingRepository()..nextResult = const FailureResult(NetworkFailure());
    await launch(tester, appContainer(onboarding));
    expect(find.byType(OfflineScreen), findsOneWidget);

    onboarding.nextResult = const Success(OnboardingStep.complete);
    await tester.tap(find.text(AppLocalizationsKo().commonRetry));
    await tester.pumpAndSettle();

    expect(find.byType(OfflineScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
