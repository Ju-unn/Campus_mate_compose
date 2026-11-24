import 'dart:convert';

import 'package:campus_mate/auth/gate/model/data/verification_gate.dart';
import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository_provider.dart';
import 'package:campus_mate/billing/store/model/repository/billing_repository_provider.dart';
import 'package:campus_mate/billing/store/model/repository/heart_store_gateway.dart';
import 'package:campus_mate/billing/store/viewmodel/heart_purchase_view_model.dart';
import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/app_update/app_version.dart';
import 'package:campus_mate/core/app_update/app_version_repository.dart';
import 'package:campus_mate/core/app_update/installed_app_version.dart';
import 'package:campus_mate/core/app_update/update_requirement_provider.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/graduate/view/graduate_waiting_screen.dart';
import 'package:campus_mate/home/model/repository/home_repository_provider.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/notifications/model/repository/notifications_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:flutter/material.dart' show AppLifecycleState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/gate/model/repository/fake_verification_gate_repository.dart';
import 'billing/store/model/repository/fake_billing_repository.dart';
import 'billing/store/model/repository/fake_heart_store_gateway.dart';
import 'chat/model/repository/fake_chat_repository.dart';
import 'core/push/fake_push_messaging.dart';
import 'home/model/repository/fake_home_repository.dart';
import 'matching/model/repository/fake_card_repository.dart';
import 'notifications/model/repository/fake_notifications_repository.dart';
import 'profile/onboarding/model/repository/fake_onboarding_repository.dart';

class _InstalledVersion implements InstalledAppVersion {
  @override
  Future<AppVersion?> read() async => AppVersion.tryParse('1.0.7');
}

/// 앱 시작 · 복귀 때 경로별로 서버를 몇 번 부르는지 못박는다(1.0.7 #6, 11-17 기록 "2초 안 재호출 17%").
/// 숫자가 다시 늘면 여기서 잡힌다. 각 저장소 · 가짜 HTTP 가 센 횟수만 본다 — 서버 · 운영과는 닿지 않는다.
void main() {
  // main_session_refresh_test.dart 와 같은 더미 초기화 — CampusMateApp 이 Supabase 세션을 직접 읽는다.
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

  setUp(() => auth().setInitialSession(jsonEncode({
        'access_token': 'test-access-token-u1',
        'token_type': 'bearer',
        'user': {'id': 'u1', 'aud': 'authenticated', 'created_at': '2026-11-24T00:00:00Z'},
      })));
  tearDown(() async {
    try {
      await auth().signOut();
    } on AuthException {
      // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
    }
  });

  late FakeVerificationGateRepository gate;
  late FakeOnboardingRepository steps;
  late FakeCardRepository cards;
  late FakeChatRepository chat;
  late FakeUserEventStream events;
  late FakeNotificationsRepository notifications;
  late FakeHeartStoreGateway store;
  late int versionCalls;

  Map<String, int> counts() => {
        'version': versionCalls,
        'gate': gate.fetchCount,
        'step': steps.fetchCount,
        'conversations': chat.conversationsFetchCount,
        'acceptances': cards.fetchAcceptancesCount,
        'unread': notifications.countCalls,
        'purchaseRecover': store.recoverCount,
      };

  Map<String, int> since(Map<String, int> before) => {
        for (final MapEntry(:key, :value) in counts().entries) key: value - before[key]!,
      };

  /// 관문을 연 사용자로 켜고, 사용자 채널이 붙을 때까지 기다린다.
  Future<void> pumpApp(WidgetTester tester, {VerificationGate opened = VerificationGate.complete}) async {
    gate = FakeVerificationGateRepository()..nextResult = Success(opened);
    steps = FakeOnboardingRepository();
    cards = FakeCardRepository();
    chat = FakeChatRepository();
    events = FakeUserEventStream();
    notifications = FakeNotificationsRepository();
    store = FakeHeartStoreGateway();
    versionCalls = 0;
    final versionClient = MockClient((request) async {
      versionCalls++;
      return http.Response('{"min_version":"1.0.6"}', 200);
    });
    final container = ProviderContainer(overrides: [
      appVersionRepositoryProvider.overrideWithValue(AppVersionRepository('https://api.test', versionClient)),
      installedAppVersionProvider.overrideWithValue(_InstalledVersion()),
      verificationGateRepositoryProvider.overrideWithValue(gate),
      onboardingRepositoryProvider.overrideWithValue(steps),
      pushMessagingProvider.overrideWithValue(FakePushMessaging(token: 't', granted: false)),
      cardRepositoryProvider.overrideWithValue(cards),
      chatRepositoryProvider.overrideWithValue(chat),
      userEventStreamProvider.overrideWithValue(events),
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
      notificationsRepositoryProvider.overrideWithValue(notifications),
      heartStoreGatewayProvider.overrideWithValue(store),
      billingRepositoryProvider.overrideWithValue(FakeBillingRepository()),
      heartPurchaseSupportedProvider.overrideWithValue(true),
      signOutProvider.overrideWithValue(() async {}),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    // 스플래시(SplashHold 2초)를 지나 지난 세션 알림까지 모두 받는다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    // 관문을 연 사용자가 보이는 앱으로 켜졌을 때만 채널을 건다.
    if (events.openCount > 0) {
      events.connect();
      await tester.pumpAndSettle();
    }
  }

  Future<void> moveThrough(WidgetTester tester, List<AppLifecycleState> states) async {
    // AppLifecycleListener 는 한 칸씩 옮겨 가야 받는다(건너뛰면 assert).
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    // supabase_flutter 가 복귀 때 켠 토큰 자동 갱신 타이머를 끈다 — 시험 끝에 남은 타이머로 실패하지 않게.
    auth().stopAutoRefresh();
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();
  }

  /// 홈 버튼 · 다른 앱으로 갔다가 돌아온다 — 화면에서 사라진다(hidden).
  Future<void> returnFromBackground(WidgetTester tester) async {
    await moveThrough(tester, const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    // 복귀 때 다시 건 사용자 채널이 붙는다(관문을 연 사용자만 채널을 건다).
    if (events.openCount > 0) {
      events.connect();
      await tester.pumpAndSettle();
    }
  }

  /// 알림 센터 · 시스템 창 · 결제 창이 잠깐 덮었다 걷힌다 — 화면에서 사라지지 않는다(inactive 만).
  Future<void> returnFromOverlay(WidgetTester tester) =>
      moveThrough(tester, const [AppLifecycleState.inactive, AppLifecycleState.resumed]);

  testWidgets('켤 때(콜드 스타트) — 버전 · 관문 · 가입 단계는 한 번씩', (tester) async {
    await pumpApp(tester);

    expect(counts(), {
      'version': 1,
      'gate': 1,
      'step': 1,
      // 1.0.7 뒤 줄일 예정(사용자 「1.0.7 뒤로 미루기」): 첫 읽기 + 사용자 채널이 붙을 때 메우는 읽기.
      'conversations': 2,
      'acceptances': 2,
      'unread': 1,
      'purchaseRecover': 1,
    });
  });

  testWidgets('백그라운드에서 돌아오면 복귀 일을 한 번씩 한다', (tester) async {
    await pumpApp(tester);
    final before = counts();

    await returnFromBackground(tester);

    expect(since(before), {
      'version': 1,
      'gate': 1,
      'step': 0,
      // 1.0.7 뒤 줄일 예정(사용자 「1.0.7 뒤로 미루기」): 복귀 읽기 + 다시 붙은 채널이 메우는 읽기.
      'conversations': 2,
      'acceptances': 2,
      'unread': 1,
      'purchaseRecover': 1,
    });
  });

  testWidgets('잠깐 덮였다 걷히면(inactive 만) 결제 복구만 한다 — 채널이 그대로라 다시 읽을 것이 없다', (tester) async {
    await pumpApp(tester);
    final before = counts();

    await returnFromOverlay(tester);

    expect(since(before), {
      'version': 0,
      'gate': 0,
      'step': 0,
      'conversations': 0,
      'acceptances': 0,
      'unread': 0,
      // 결제 창(구글 플레이 · 애플)이 바로 이 경우다 — 늦게 온 결제를 이어 받는다.
      'purchaseRecover': 1,
    });
  });

  testWidgets('백그라운드에서 돌아온 뒤 잠깐 덮였다 걷히면 결제 복구만 한다 — 복귀 표시는 한 번 쓰고 지운다', (tester) async {
    await pumpApp(tester);
    await returnFromBackground(tester);
    final before = counts();

    await returnFromOverlay(tester);

    expect(since(before), {
      'version': 0,
      'gate': 0,
      'step': 0,
      'conversations': 0,
      'acceptances': 0,
      'unread': 0,
      'purchaseRecover': 1,
    });
  });

  testWidgets('잠깐 덮였다 걷힌 뒤 백그라운드에서 돌아오면 다시 복귀 일을 한다', (tester) async {
    await pumpApp(tester);
    await returnFromOverlay(tester);
    final before = counts();

    await returnFromBackground(tester);

    expect(since(before)['version'], 1);
    expect(since(before)['gate'], 1);
  });

  group('졸업생 대기 화면(관문 graduateReviewing)', () {
    testWidgets('돌아오면 관문을 한 번만 묻는다 — 앱 루트가 묻고 화면은 따로 묻지 않는다', (tester) async {
      await pumpApp(tester, opened: VerificationGate.graduateReviewing);
      expect(find.byType(GraduateWaitingScreen), findsOneWidget);
      final before = gate.fetchCount;

      await returnFromBackground(tester);

      expect(gate.fetchCount - before, 1);
    });

    testWidgets('돌아왔을 때 승인돼 있으면 곧바로 대기 화면을 떠난다', (tester) async {
      await pumpApp(tester, opened: VerificationGate.graduateReviewing);
      gate.nextResult = const Success(VerificationGate.complete);

      await returnFromBackground(tester);

      expect(find.byType(GraduateWaitingScreen), findsNothing);
    });

    testWidgets('켜 둔 채 승인되면 30초 폴링으로 대기 화면을 떠난다', (tester) async {
      await pumpApp(tester, opened: VerificationGate.graduateReviewing);
      gate.nextResult = const Success(VerificationGate.complete);

      await tester.pump(graduateWaitingPollInterval);
      await tester.pumpAndSettle();

      expect(find.byType(GraduateWaitingScreen), findsNothing);
    });
  });
}
