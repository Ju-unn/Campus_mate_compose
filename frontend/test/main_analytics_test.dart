import 'dart:convert';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/model/fake_verification_gate_repository.dart';
import 'chat/model/fake_chat_repository.dart';
import 'core/analytics/fake_analytics_service.dart';
import 'core/analytics/fake_crash_reporter.dart';
import 'core/analytics/fake_performance_monitor.dart';
import 'core/push/fake_push_messaging.dart';
import 'home/model/fake_home_repository.dart';
import 'matching/model/fake_card_repository.dart';
import 'notifications/model/fake_notifications_repository.dart';
import 'profile/model/fake_onboarding_repository.dart';

/// 사용 통계 · 오류 수집을 켜고 끄는 배선(main.dart)을 지킨다 — **약관 동의 전에는 켜지 않는다.**
/// 규칙 자체는 collection_consent_test.dart 가 보고, 여기서는 앱 루트가 세션 · 관문 변화마다 그 규칙을 부르는지만 본다.
void main() {
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

  GoTrueClient auth() => Supabase.instance.client.auth;

  late FakeAnalyticsService analytics;
  late FakeCrashReporter crashReporter;
  late FakePerformanceMonitor performance;
  late FakeVerificationGateRepository gate;

  setUp(() {
    analytics = FakeAnalyticsService();
    crashReporter = FakeCrashReporter();
    performance = FakePerformanceMonitor();
    gate = FakeVerificationGateRepository();
    return auth().setInitialSession(jsonEncode({
      'access_token': 'test-access-token',
      'token_type': 'bearer',
      'user': {'id': 'u1', 'aud': 'authenticated', 'created_at': '2026-10-20T00:00:00Z'},
    }));
  });

  tearDown(() async {
    try {
      await auth().signOut();
    } on AuthException {
      // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
    }
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(gate),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        pushMessagingProvider.overrideWithValue(FakePushMessaging(token: 't', granted: false)),
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        userEventStreamProvider.overrideWithValue(FakeUserEventStream()),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        signOutProvider.overrideWithValue(() async {}),
        analyticsServiceProvider.overrideWithValue(analytics),
        crashReporterProvider.overrideWithValue(crashReporter),
        performanceMonitorProvider.overrideWithValue(performance),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('이미 동의를 마친 로그인 상태로 앱을 켜면 관문이 정해지는 순간 켠다', (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: makeContainer(), child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(analytics.collecting, isTrue);
    expect(crashReporter.collecting, isTrue);
    expect(performance.collecting, isTrue);
  });

  testWidgets('약관 동의 전(02-c)에서는 켜지 않는다', (tester) async {
    gate.nextResult = const Success(VerificationGate.needsConsent);

    await tester.pumpWidget(UncontrolledProviderScope(container: makeContainer(), child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(analytics.collecting, isFalse);
    expect(crashReporter.collecting, isFalse);
    expect(performance.collecting, isFalse);
    expect(analytics.calls, isNot(contains('enable')));
    expect(crashReporter.calls, isNot(contains('enable')));
    expect(performance.calls, isNot(contains('enable')));
  });

  testWidgets('약관 동의를 마쳐 관문이 넘어가는 순간 켠다', (tester) async {
    gate.nextResult = const Success(VerificationGate.needsConsent);
    final container = makeContainer();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(analytics.collecting, isFalse);

    gate.nextResult = const Success(VerificationGate.needsSchoolEmail);
    await container.read(verificationGateListenableProvider).refresh();
    await tester.pumpAndSettle();

    expect(analytics.collecting, isTrue);
    expect(crashReporter.collecting, isTrue);
    expect(performance.collecting, isTrue);
  });

  testWidgets('세션이 끝나면(로그아웃 · 탈퇴) 끈다', (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: makeContainer(), child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(analytics.collecting, isTrue);

    await tester.runAsync(() async {
      try {
        await auth().signOut();
      } on AuthException {
        // 위 tearDown 과 같다.
      }
    });
    await tester.pumpAndSettle();

    expect(analytics.collecting, isFalse);
    expect(crashReporter.collecting, isFalse);
    expect(performance.collecting, isFalse);
  });
}
