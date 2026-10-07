import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/auth/model/student_verification_repository_provider.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/view/student_verification_screen.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:flutter/material.dart' show AppLifecycleState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/model/fake_student_verification_repository.dart';
import 'auth/model/fake_verification_gate_repository.dart';
import 'chat/model/fake_chat_repository.dart';
import 'core/push/fake_push_messaging.dart';
import 'home/model/fake_home_repository.dart';
import 'matching/model/fake_card_repository.dart';
import 'profile/model/fake_onboarding_repository.dart';

/// 관문 조회가 [complete] 를 부를 때까지 끝나지 않는다 — 콜드 스타트에서 서버가 늦게 답하는 모양.
class _SlowGateRepository implements VerificationGateRepository {
  final _answer = Completer<Result<VerificationGate>>();

  void complete(VerificationGate gate) => _answer.complete(Success(gate));

  @override
  Future<Result<VerificationGate>> fetchGate() => _answer.future;
}

/// 꺼진 앱에서 알림을 눌러 켰을 때(A10). 알림 경로는 관문 조회가 끝난 뒤에 열린다 —
/// 먼저 열면 조회 전 기본값(약관 동의)에 끌려갔다가 조회가 오면 홈으로 가서 목표 화면을 놓쳤다.
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

  GoTrueClient auth() => Supabase.instance.client.auth;

  setUp(() => auth().setInitialSession(jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'user': {'id': 'u1', 'aud': 'authenticated', 'created_at': '2026-10-03T00:00:00Z'},
      })));

  tearDown(() async {
    try {
      await auth().signOut();
    } on AuthException {
      // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
    }
  });

  testWidgets('관문 조회가 늦게 와도 받은 수락 알림의 대화 목록으로 간다', (tester) async {
    final gate = _SlowGateRepository();
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(gate),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        pushMessagingProvider.overrideWithValue(
          FakePushMessaging(token: 't', granted: false, initial: {'route': 'acceptances'}),
        ),
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        signOutProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    // 스플래시(SplashHold 2초)가 지나도록 관문은 아직 답하지 않았다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    gate.complete(VerificationGate.complete);
    await tester.pumpAndSettle();

    expect(find.byType(ConversationsScreen), findsOneWidget);
  });

  // A7 — 앱이 켜져 있으면 검토 결과 알림은 배너 대신 화면을 갱신한다. 없으면 30초 폴링까지 검토 중 화면에 남는다.
  late FakeVerificationGateRepository gate;
  late FakeStudentVerificationRepository verification;
  late FakePushMessaging messaging;
  // 앱 복귀 때 읽는 두 목록의 가짜 저장소 — 읽은 횟수를 본다. 두 pump 도우미가 채운다.
  late FakeChatRepository appChat;
  late FakeCardRepository appCards;

  Future<void> pumpPendingVerification(WidgetTester tester) async {
    gate = FakeVerificationGateRepository()..nextResult = const Success(VerificationGate.needsStudentVerification);
    verification = FakeStudentVerificationRepository()
      ..nextFetchStatusResult = const Success(VerificationOutcome(status: 'pending'));
    messaging = FakePushMessaging(token: 't', granted: false);
    appChat = FakeChatRepository();
    appCards = FakeCardRepository();
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(gate),
        studentVerificationRepositoryProvider.overrideWithValue(verification),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        pushMessagingProvider.overrideWithValue(messaging),
        cardRepositoryProvider.overrideWithValue(appCards),
        chatRepositoryProvider.overrideWithValue(appChat),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        signOutProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(StudentVerificationScreen), findsOneWidget);
  }

  testWidgets('검토 중 화면에서 검토 결과 알림이 오면 바로 다음 화면으로 넘어간다', (tester) async {
    await pumpPendingVerification(tester);

    verification.nextFetchStatusResult = const Success(VerificationOutcome(status: 'verified'));
    gate.nextResult = const Success(VerificationGate.complete);
    messaging.emitMessage({'route': 'verification'});
    await tester.pumpAndSettle();

    expect(find.byType(StudentVerificationScreen), findsNothing);
  });

  // 관문만 다시 물으면 거절은 그대로 needsStudentVerification 이라 화면이 안 바뀐다 — 3b 상태까지 다시 읽어야 한다.
  testWidgets('검토 중 화면에서 거절 알림이 오면 바로 거절 배너를 보여준다', (tester) async {
    await pumpPendingVerification(tester);

    verification.nextFetchStatusResult =
        const Success(VerificationOutcome(status: 'rejected', rejectReason: '사진이 흐려요'));
    messaging.emitMessage({'route': 'verification'});
    await tester.pumpAndSettle();

    expect(find.text('인증이 거절됐어요'), findsOneWidget);
  });

  // 알림을 눌러 열면 화면만 옮기고 목록은 낡은 채로 남았다 — 대화 탭은 들어갈 때 다시 읽지 않는다.
  Future<(FakeChatRepository, FakePushMessaging)> pumpHome(WidgetTester tester) async {
    final chat = appChat = FakeChatRepository();
    appCards = FakeCardRepository();
    final push = FakePushMessaging(token: 't', granted: false);
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        pushMessagingProvider.overrideWithValue(push),
        cardRepositoryProvider.overrideWithValue(appCards),
        chatRepositoryProvider.overrideWithValue(chat),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        signOutProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    return (chat, push);
  }

  Conversation conversationWith(String nickname) => Conversation(
        matchId: 'm1',
        partner: ChatPartner(profileId: 'p1', nickname: nickname),
        lastMessageAt: DateTime(2026, 10, 5),
        unreadCount: 0,
        trustPassed: false,
        remainingSeconds: 3600,
      );

  testWidgets('매칭 알림을 눌러 열면 대화 목록을 다시 읽어 새 방이 보인다', (tester) async {
    final (chat, push) = await pumpHome(tester);
    final before = chat.conversationsFetchCount;
    chat.conversations = Success([conversationWith('새연결')]);

    push.emitOpened({'route': 'match', 'match_id': 'm1'});
    await tester.pumpAndSettle();

    expect(find.byType(ConversationsScreen), findsOneWidget);
    // 알림이 한 번, 화면에 들어서며 한 번 — 몇 번이든 새 목록을 읽어 와야 한다.
    expect(chat.conversationsFetchCount, greaterThan(before));
    expect(find.text('새연결'), findsOneWidget);
  });

  // 홈 같은 다른 탭에 있어도 앱이 백그라운드에서 돌아오면 하단 내비 "대화" 숫자가 낡지 않게 다시 읽는다.
  void sendReturnFromBackground(WidgetTester tester) {
    // AppLifecycleListener 는 한 칸씩 넘어가는 순서만 받는다 — 기기와 같은 순서로 보낸다.
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
  }

  Future<void> returnFromBackground(WidgetTester tester) async {
    sendReturnFromBackground(tester);
    await tester.pumpAndSettle();
    // 돌아오면 Supabase 도 토큰 자동 갱신 타이머를 켠다 — 테스트가 끝나기 전에 끈다.
    auth().stopAutoRefresh();
  }

  testWidgets('다른 탭에서 앱이 백그라운드에서 돌아와도 대화 목록과 수락 대기를 다시 읽는다', (tester) async {
    final (chat, _) = await pumpHome(tester);
    expect(find.byType(ConversationsScreen), findsNothing);
    final before = chat.conversationsFetchCount;
    final cardsBefore = appCards.fetchAcceptancesCount;

    await returnFromBackground(tester);

    expect(chat.conversationsFetchCount, before + 1);
    expect(appCards.fetchAcceptancesCount, cardsBefore + 1);
  });

  // 관문이 끝나지 않은 계정은 대화 조회가 403 일 수 있다 — 앱 루트가 현재 관문 값을 넘기는지 본다.
  testWidgets('관문이 끝나지 않은 화면에서 앱이 돌아오면 대화 목록과 수락 대기를 읽지 않는다', (tester) async {
    await pumpPendingVerification(tester);
    expect(appChat.conversationsFetchCount, 0);
    expect(appCards.fetchAcceptancesCount, 0);

    await returnFromBackground(tester);

    expect(appChat.conversationsFetchCount, 0);
    expect(appCards.fetchAcceptancesCount, 0);
  });

  // 로그아웃하면 세션 변화가 관문도 되돌린다 — 그래서 이 시험은 `isAuthenticated` 와 `gate` 중 어느 한쪽 가드가 빠져도
  // 통과한다(둘이 같이 닫힌다). 로그아웃 뒤 "읽지 않는다"는 앱 전체 결과만 고정한다.
  testWidgets('로그아웃한 직후 앱이 돌아오면 대화 목록과 수락 대기를 읽지 않는다', (tester) async {
    final (chat, _) = await pumpHome(tester);
    final before = chat.conversationsFetchCount;
    final cardsBefore = appCards.fetchAcceptancesCount;

    // 테스트 시계 안에서는 실제 입출력 future 가 끝나지 않는다 — runAsync 로 돌린다.
    await tester.runAsync(() async {
      try {
        await auth().signOut();
      } on AuthException {
        // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
      }
    });
    expect(auth().currentSession, isNull);
    sendReturnFromBackground(tester);
    await tester.pump(const Duration(milliseconds: 100));
    auth().stopAutoRefresh();

    expect(chat.conversationsFetchCount, before);
    expect(appCards.fetchAcceptancesCount, cardsBefore);
  });
}
