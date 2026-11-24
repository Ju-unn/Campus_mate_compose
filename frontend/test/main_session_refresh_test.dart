import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/auth/gate/model/data/verification_gate.dart';
import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository_provider.dart';
import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/home/model/repository/home_repository_provider.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/notifications/model/repository/notifications_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:flutter/material.dart' show AppLifecycleState;
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

/// 앱 루트가 관문(`/me/verification-status`) · 가입 단계(`/profile-onboarding/next-step`)를 언제 다시 묻는지 지킨다(1.0.7 #6 ①).
/// gotrue 의 세션 알림은 지난 이벤트를 다시 주는 스트림이라, 켤 때 이미 나간 initialSession 을 한 박자 늦게 또 받는다 —
/// 로그인 여부 · 사용자가 바뀔 때와 앞 조회가 실패했을 때만 다시 묻는다.
void main() {
  // main_push_open_test.dart 와 같은 더미 초기화 — CampusMateApp 이 Supabase 세션을 직접 읽는다.
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

  // 토큰은 JWT 가 아니라 만료 시각을 못 읽는다 — gotrue 가 갱신하러 나가지 않는다.
  Future<void> signIn(String userId) => auth().setInitialSession(jsonEncode({
        'access_token': 'test-access-token-$userId',
        'token_type': 'bearer',
        'user': {'id': userId, 'aud': 'authenticated', 'created_at': '2026-11-24T00:00:00Z'},
      }));

  // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
  Future<void> signOut() async {
    try {
      await auth().signOut();
    } on AuthException {
      // 위 주석.
    }
  }

  setUp(() => signIn('u1'));
  tearDown(signOut);

  late FakeVerificationGateRepository gate;
  late FakeOnboardingRepository steps;
  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(gate),
        onboardingRepositoryProvider.overrideWithValue(steps),
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
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    // 스플래시(SplashHold 2초)를 지나 지난 세션 알림까지 모두 받는다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  /// 같은 사용자의 토큰 갱신 — gotrue 가 한 시간쯤마다 보낸다.
  Future<void> refreshToken(WidgetTester tester) async {
    // gotrue 안에서만 부르라는 표시(@internal)지만, 토큰 갱신 알림을 서버 없이 그대로 흉내 낼 길이 이것뿐이다.
    // ignore: invalid_use_of_internal_member
    auth().notifyAllSubscribers(AuthChangeEvent.tokenRefreshed);
    await tester.pumpAndSettle();
  }

  Future<void> signOutAndSettle(WidgetTester tester) async {
    await tester.runAsync(signOut);
    await tester.pumpAndSettle();
  }

  setUp(() {
    gate = FakeVerificationGateRepository();
    steps = FakeOnboardingRepository();
  });

  testWidgets('켤 때 관문 · 가입 단계는 한 번씩만 묻는다', (tester) async {
    await pumpApp(tester);

    expect((gate.fetchCount, steps.fetchCount), (1, 1));
  });

  testWidgets('같은 사용자의 토큰 갱신에는 다시 묻지 않는다', (tester) async {
    await pumpApp(tester);

    await refreshToken(tester);

    expect((gate.fetchCount, steps.fetchCount), (1, 1));
  });

  testWidgets('로그아웃하면 관문 · 단계를 비우고, 다른 사용자로 로그인하면 다시 묻는다', (tester) async {
    await pumpApp(tester);

    await signOutAndSettle(tester);
    expect(container.read(verificationGateListenableProvider).value, VerificationGate.unknown);
    expect(container.read(onboardingStepListenableProvider).value, isNull);

    await signIn('u2');
    await tester.pumpAndSettle();

    expect((gate.fetchCount, steps.fetchCount), (2, 2));
  });

  testWidgets('로그아웃했다가 같은 사용자로 다시 로그인해도 다시 묻는다', (tester) async {
    await pumpApp(tester);

    await signOutAndSettle(tester);
    await signIn('u1');
    await tester.pumpAndSettle();

    expect((gate.fetchCount, steps.fetchCount), (2, 2));
  });

  testWidgets('로그아웃 없이 다른 사용자로 바뀌어도 다시 묻는다', (tester) async {
    await pumpApp(tester);

    await signIn('u2');
    await tester.pumpAndSettle();

    expect((gate.fetchCount, steps.fetchCount), (2, 2));
  });

  testWidgets('관문 조회가 실패했으면 토큰 갱신 때 다시 묻는다', (tester) async {
    gate.nextResult = const FailureResult(NetworkFailure());
    await pumpApp(tester);
    expect(container.read(verificationGateListenableProvider).value, VerificationGate.unreachable);

    gate.nextResult = const Success(VerificationGate.complete);
    await refreshToken(tester);

    expect(gate.fetchCount, 2);
    expect(container.read(verificationGateListenableProvider).value, VerificationGate.complete);
  });

  testWidgets('가입 단계 조회가 실패했으면 토큰 갱신 때 다시 묻는다', (tester) async {
    steps.nextResult = const FailureResult(NetworkFailure());
    await pumpApp(tester);
    expect(container.read(onboardingStepListenableProvider).isUnreachable, isTrue);

    steps.nextResult = const Success(OnboardingStep.complete);
    await refreshToken(tester);

    expect(steps.fetchCount, 2);
    expect(container.read(onboardingStepListenableProvider).isUnreachable, isFalse);
  });

  testWidgets('실패 뒤 다시 물어 답을 받으면, 그다음 토큰 갱신에는 묻지 않는다', (tester) async {
    gate.nextResult = const FailureResult(NetworkFailure());
    await pumpApp(tester);
    gate.nextResult = const Success(VerificationGate.complete);
    await refreshToken(tester);

    await refreshToken(tester);

    expect(gate.fetchCount, 2);
  });

  testWidgets('사용자가 바뀐 뒤 앞 사용자의 늦은 관문 답은 새 사용자의 실패 표시를 덮지 않는다', (tester) async {
    gate.nextResult = const FailureResult(NetworkFailure());
    await pumpApp(tester);
    // u1 의 다시 묻기가 느리게 날아가는 사이에
    final slowAsk = gate.holdFetch = Completer<void>();
    gate.nextResult = const Success(VerificationGate.complete);
    await refreshToken(tester);
    // u2 로 바뀌고 u2 의 조회는 실패한다.
    gate
      ..holdFetch = null
      ..nextResult = const FailureResult(NetworkFailure());
    await signIn('u2');
    await tester.pumpAndSettle();
    // 그 뒤에 u1 의 답(성공)이 늦게 온다.
    gate.nextResult = const Success(VerificationGate.complete);
    slowAsk.complete();
    await tester.pumpAndSettle();

    await refreshToken(tester);

    expect(gate.fetchCount, 4, reason: 'u2 는 실패했으니 토큰 갱신 때 다시 묻는다');
  });

  /// 앱이 뒤로 갔다가 다시 앞으로 온다.
  Future<void> resume(WidgetTester tester) async {
    // AppLifecycleListener 는 한 칸씩 옮겨 가야 받는다(건너뛰면 assert).
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    // supabase_flutter 가 복귀 때 켠 토큰 자동 갱신 타이머(10초 주기)를 끈다 — 시험 끝에 남은 타이머로 실패하지 않게.
    // 갱신 첫 확인은 0초 타이머라 시간을 흘려 끝낸다(인자 없는 pump 는 타이머를 돌리지 않는다).
    auth().stopAutoRefresh();
    await tester.pump(Duration.zero);
  }

  testWidgets('앱으로 돌아오면 관문만 한 번 다시 묻는다 — 가입 단계는 묻지 않는다', (tester) async {
    await pumpApp(tester);

    await resume(tester);
    await tester.pumpAndSettle();

    expect((gate.fetchCount, steps.fetchCount), (2, 1));
  });

  testWidgets('관문 조회가 날아가는 중에 다시 돌아와도 하나 더 보내지 않는다', (tester) async {
    await pumpApp(tester);
    final slowAsk = gate.holdFetch = Completer<void>();

    await resume(tester);
    await resume(tester);
    expect(gate.fetchCount, 2);

    gate.holdFetch = null;
    slowAsk.complete();
    await tester.pumpAndSettle();
    await resume(tester);
    expect(gate.fetchCount, 3, reason: '앞 조회가 끝났으면 다음 복귀에 다시 묻는다');
  });

  testWidgets('로그아웃한 채 돌아오면 관문을 묻지 않는다', (tester) async {
    await pumpApp(tester);
    await signOutAndSettle(tester);

    await resume(tester);
    await tester.pumpAndSettle();

    expect(gate.fetchCount, 1);
  });
}
