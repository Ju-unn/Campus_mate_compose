import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/auth/school_info/model/repository/school_name_provider.dart';
import 'package:campus_mate/auth/gate/model/data/verification_gate.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/auth/school_info/view/school_info_screen.dart';
import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository.dart';
import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository_provider.dart';
import 'package:campus_mate/billing/task/model/repository/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/task/view/heart_tasks_screen.dart';
import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/data/conversation.dart';
import 'package:campus_mate/chat/model/data/message.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/chat/viewmodel/user_channel.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/home/model/data/cohort_wait.dart';
import 'package:campus_mate/home/model/data/home_summary.dart';
import 'package:campus_mate/home/model/repository/home_repository_provider.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/faq/model/repository/faq_cache.dart';
import 'package:campus_mate/faq/model/repository/faq_repository.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/view/settings_screen.dart';
import 'package:campus_mate/me/model/repository/me_repository_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:campus_mate/notifications/model/repository/notifications_repository_provider.dart';
import 'package:flutter/material.dart' show AppLifecycleState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:campus_mate/chat/model/data/user_event.dart';

import 'auth/gate/model/repository/fake_verification_gate_repository.dart';
import 'billing/task/model/repository/fake_heart_task_repository.dart';
import 'chat/model/repository/fake_chat_repository.dart';
import 'core/analytics/fake_analytics_service.dart';
import 'core/push/fake_push_messaging.dart';
import 'core/push/fake_system_notifications.dart';
import 'faq/model/repository/fake_faq.dart';
import 'me/model/repository/fake_me_repository.dart';
import 'home/model/repository/fake_home_repository.dart';
import 'matching/model/repository/fake_card_repository.dart';
import 'profile/onboarding/model/repository/fake_onboarding_repository.dart';
import 'notifications/model/repository/fake_notifications_repository.dart';

/// 관문 조회가 [complete] 를 부를 때까지 끝나지 않는다 — 콜드 스타트에서 서버가 늦게 답하는 모양.
class _SlowGateRepository implements VerificationGateRepository {
  final _answer = Completer<Result<VerificationGate>>();

  void complete(VerificationGate gate) => _answer.complete(Success(gate));

  @override
  Future<Result<VerificationGate>> fetchGate() => _answer.future;
}

/// 방 id(지어낸 UUID). 라우터는 UUID 모양이 아닌 방 id 를 대화 목록으로 돌려보낸다(2026-10-18 경로 id 검사).
const _roomId = '11111111-1111-4111-8111-111111111111';
const _otherRoomId = '22222222-2222-4222-8222-222222222222';

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
        userEventStreamProvider.overrideWithValue(FakeUserEventStream()),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
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

  late FakeVerificationGateRepository gate;
  late FakePushMessaging messaging;
  // 앱 복귀 때 읽는 두 목록의 가짜 저장소 — 읽은 횟수를 본다. 두 pump 도우미가 채운다.
  late FakeChatRepository appChat;
  late FakeCardRepository appCards;
  // 홈 종 배지가 읽는 안 읽은 알림 수의 가짜 저장소 — 읽은 횟수를 본다. 두 pump 도우미가 채운다.
  late FakeNotificationsRepository appNotifications;
  // 사용자 채널(`user:<내 id>`, 설계안 A) 자리의 가짜와 앱 컨테이너 — 두 pump 도우미가 채운다.
  late FakeUserEventStream appEvents;
  late ProviderContainer appContainer;
  // 앱이 떠 있을 때 받은 푸시를 안드로이드가 띄우는 시스템 알림 창구. 두 pump 도우미가 채운다.
  late FakeSystemNotifications appSystemNotifications;
  // 사용 통계 push_open 을 보려는 가짜. pumpHome 이 채운다.
  late FakeAnalyticsService appAnalytics;
  // 홈 요약 가짜 — 시험 도중 요약을 바꿔 다시 읽게 한다. pumpHome 이 채운다.
  late FakeHomeRepository appHome;

  /// 관문이 아직 끝나지 않은 앱(학교 메일은 인증했고 학과 · 학번 3c 가 남았다).
  Future<void> pumpGatedApp(WidgetTester tester) async {
    gate = FakeVerificationGateRepository()..nextResult = const Success(VerificationGate.needsSchoolInfo);
    messaging = FakePushMessaging(token: 't', granted: false);
    appChat = FakeChatRepository();
    appCards = FakeCardRepository();
    appNotifications = FakeNotificationsRepository();
    appEvents = FakeUserEventStream();
    appSystemNotifications = FakeSystemNotifications();
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(gate),
        schoolNameProvider.overrideWithValue(const AsyncData<String>('서울대학교')),
        // 3c 학교 줄(SchoolLabel)이 로고 표를 읽는다 — 진짜 Supabase 조회가 실패해 재시도 타이머가 남지 않게.
        universityLogosProvider.overrideWith((ref) => const <String, String>{}),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        pushMessagingProvider.overrideWithValue(messaging),
        systemNotificationsProvider.overrideWithValue(appSystemNotifications),
        cardRepositoryProvider.overrideWithValue(appCards),
        chatRepositoryProvider.overrideWithValue(appChat),
        userEventStreamProvider.overrideWithValue(appEvents),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        notificationsRepositoryProvider.overrideWithValue(appNotifications),
        signOutProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SchoolInfoScreen), findsOneWidget);
  }

  // 10-17 학생증 제거: 옛 학생증 결과 알림(route verification)이 와도 앱은 아무 일도 하지 않는다 — 화면도 알림 줄도 그대로.
  testWidgets('옛 학생증 결과 알림이 와도 화면을 옮기거나 알림 줄을 지우지 않는다', (tester) async {
    await pumpGatedApp(tester);

    messaging.emitMessage({'route': 'verification'}, title: '학교 인증이 끝났어요', body: '학과 정보를 입력하고 시작해 보세요');
    await tester.pumpAndSettle();

    expect(find.byType(SchoolInfoScreen), findsOneWidget);
    expect(appSystemNotifications.cancelled, isEmpty);
  });

  // 알림을 눌러 열면 화면만 옮기고 목록은 낡은 채로 남았다 — 대화 탭은 들어갈 때 다시 읽지 않는다.
  // [launch] 는 꺼진 앱을 앱이 직접 띄운 알림으로 켰다고 흉내 낸다.
  Future<(FakeChatRepository, FakePushMessaging)> pumpHome(
    WidgetTester tester, {
    Map<String, dynamic>? launch,
    Result<HomeSummary> summary = const FailureResult(NetworkFailure()),
  }) async {
    final chat = appChat = FakeChatRepository()..room = Success(roomFixture());
    appCards = FakeCardRepository();
    appNotifications = FakeNotificationsRepository(unreadCount: 3);
    appSystemNotifications = FakeSystemNotifications(launch: launch);
    appEvents = FakeUserEventStream();
    appAnalytics = FakeAnalyticsService();
    final push = FakePushMessaging(token: 't', granted: false);
    appHome = FakeHomeRepository(summary);
    final container = appContainer = ProviderContainer(
      overrides: [
        analyticsServiceProvider.overrideWithValue(appAnalytics),
        // 설정(16)을 여는 시험이 내 프로필 · FAQ 를 읽는다 — 실제 서버 · 파일로 나가지 않게 막아 둔다.
        meRepositoryProvider.overrideWithValue(FakeMeRepository(const FailureResult(NetworkFailure()))),
        faqRepositoryProvider.overrideWithValue(FakeFaqRepository(const Success(faqFixture))),
        faqCacheProvider.overrideWithValue(FakeFaqCache()),
        verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        pushMessagingProvider.overrideWithValue(push),
        systemNotificationsProvider.overrideWithValue(appSystemNotifications),
        heartTaskRepositoryProvider.overrideWithValue(FakeHeartTaskRepository()),
        cardRepositoryProvider.overrideWithValue(appCards),
        chatRepositoryProvider.overrideWithValue(chat),
        messageStreamProvider.overrideWithValue(FakeMessageStream()),
        userEventStreamProvider.overrideWithValue(appEvents),
        homeRepositoryProvider.overrideWithValue(appHome),
        notificationsRepositoryProvider.overrideWithValue(appNotifications),
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
        matchId: _roomId,
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

    push.emitOpened({'route': 'match', 'match_id': _roomId});
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
    await pumpGatedApp(tester);
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

  // 앱이 켜진 채 푸시가 오면 홈 종 배지가 바로 맞는다 — 예전에는 홈 진입 · 앱 재개 · 알림함 복귀 때만 읽었다.
  testWidgets('앱이 켜진 채 푸시가 오면 홈 종 배지의 안 읽은 알림 수를 다시 읽는다', (tester) async {
    final (_, push) = await pumpHome(tester);
    final before = appNotifications.countCalls;
    appNotifications.unreadCount = 5;

    push.emitMessage({'route': 'acceptances', 'card_id': 'c1'});
    await tester.pumpAndSettle();

    expect(appNotifications.countCalls, before + 1);
    expect(find.text('5'), findsOneWidget);
  });

  // 2026-10-13 사용자 요청: 앱이 떠 있어도 알림이 보이게 한다(조각 4 계획서의 "배너를 띄우지 않는다" 를 뒤집었다).
  testWidgets('앱이 켜진 채 받은 푸시를 시스템 알림으로 띄우고 목록 갱신 · 종 배지도 그대로 한다', (tester) async {
    final (_, push) = await pumpHome(tester);
    final before = appNotifications.countCalls;
    final acceptancesBefore = appCards.fetchAcceptancesCount;

    push.emitMessage({'route': 'acceptances', 'card_id': 'c1'}, title: '대화 신청이 왔어요', body: '새연결님이 신청했어요');
    await tester.pumpAndSettle();

    expect(appSystemNotifications.shown.single.title, '대화 신청이 왔어요');
    expect(appSystemNotifications.shown.single.data['route'], 'acceptances');
    expect(appNotifications.countCalls, before + 1);
    expect(appCards.fetchAcceptancesCount, greaterThan(acceptancesBefore));
  });

  // 대화 목록에서 방을 누르면 push 로 열린다 — 라우터의 맨 위 화면으로 지금 방을 알아야 한다.
  testWidgets('지금 열려 있는 채팅방의 새 메시지는 시스템 알림으로 띄우지 않고, 다른 방 메시지는 띄운다', (tester) async {
    final (chat, push) = await pumpHome(tester);
    chat.conversations = Success([conversationWith('새연결')]);
    push.emitOpened({'route': 'match'});
    await tester.pumpAndSettle();
    await tester.tap(find.text('새연결'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatRoomScreen), findsOneWidget);

    push.emitMessage({'route': 'chat', 'match_id': _roomId}, title: '새연결', body: '안녕하세요');
    await tester.pumpAndSettle();
    expect(appSystemNotifications.shown, isEmpty);

    push.emitMessage({'route': 'chat', 'match_id': _otherRoomId}, title: '다른사람', body: '반가워요');
    await tester.pumpAndSettle();
    expect(appSystemNotifications.shown.single.data['match_id'], _otherRoomId);
  });

  testWidgets('앱이 직접 띄운 알림을 누르면 FCM 알림을 누른 것과 같은 화면으로 간다', (tester) async {
    final (chat, _) = await pumpHome(tester);
    final before = chat.conversationsFetchCount;
    chat.conversations = Success([conversationWith('새연결')]);

    appSystemNotifications.emitTap({'route': 'match', 'match_id': _roomId});
    await tester.pumpAndSettle();

    expect(find.byType(ConversationsScreen), findsOneWidget);
    expect(chat.conversationsFetchCount, greaterThan(before));
    expect(find.text('새연결'), findsOneWidget);
  });

  testWidgets('앱이 직접 띄운 알림을 눌러 꺼진 앱을 켜면 그 화면으로 간다', (tester) async {
    await pumpHome(tester, launch: {'route': 'acceptances'});

    expect(find.byType(ConversationsScreen), findsOneWidget);
  });

  // 2026-10-19 사용자: 인증샷 승인 알림을 눌러 들어가면 뒤로가기가 없었다 — 알림 → 화면 → 뒤로가기 → 홈.
  Future<void> expectBackGoesHome(WidgetTester tester) async {
    expect(find.byType(HeartTasksScreen), findsOneWidget);
    // 실제 앱(CampusMateApp)은 한국어 머티리얼 위임자를 켜서 뒤로가기 툴팁이 "뒤로" 다(1.0.2 B8).
    expect(find.byTooltip('뒤로'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.byType(HeartTasksScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  testWidgets('인증샷 승인 알림을 눌러 열면 뒤로가기가 있고 홈으로 돌아간다(앱이 떠 있거나 백그라운드)', (tester) async {
    final (_, push) = await pumpHome(tester);

    push.emitOpened({'route': 'heart_tasks', 'task': 'everytime_post'});
    await tester.pumpAndSettle();

    await expectBackGoesHome(tester);
  });

  testWidgets('인증샷 승인 알림으로 꺼진 앱을 켜도 뒤로가기가 홈으로 간다', (tester) async {
    await pumpHome(tester, launch: {'route': 'heart_tasks', 'task': 'everytime_post'});

    await expectBackGoesHome(tester);
  });

  // 출시 전 막기(사용자 결정 11-11 「대기 화면 + 설정만」) — 학교가 열리기 전에는 알림을 눌러도 홈(19 대기) 한 장에 선다.
  group('학교 오픈 전(코호트 대기)', () {
    final waiting = Success(HomeSummary(
      deliveredCards: 0,
      signups: 0,
      conversationsStarted: 0,
      reviewRating: 0,
      reviewCount: 0,
      campuses: const [],
      profileCompletionPercent: 60,
      cohort: CohortWait(firstCardAt: DateTime.now().add(const Duration(days: 3)), recruitCount: 5),
    ));

    /// 홈이 한 장만 있다 — 막힌 경로를 push 하면 라우터가 홈을 한 겹 더 쌓는다(가려진 페이지까지 센다).
    void expectSingleWaitingHome(WidgetTester tester) {
      expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
      expect(find.byType(CohortWaitView), findsOneWidget);
    }

    /// 대기 화면 토끼가 계속 떠올라(19 `h9Hu7N`) pumpAndSettle 이 끝나지 않는다 — 이 묶음은 경로만 보므로 기기 "동작 줄이기"로 세운다.
    void testStill(String description, WidgetTesterCallback body) => testWidgets(description, (tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
          await body(tester);
        });

    testStill('떠 있는 앱에서 인증샷 승인 알림을 눌러도 18a 가 아니라 홈 한 장이다', (tester) async {
      final (_, push) = await pumpHome(tester, summary: waiting);
      expectSingleWaitingHome(tester);

      push.emitOpened({'route': 'heart_tasks', 'task': 'everytime_post'});
      await tester.pumpAndSettle();

      expect(find.byType(HeartTasksScreen, skipOffstage: false), findsNothing);
      expectSingleWaitingHome(tester);
    });

    testStill('떠 있는 앱에서 채팅 알림을 눌러도 방이 아니라 홈 한 장이다', (tester) async {
      final (_, push) = await pumpHome(tester, summary: waiting);

      push.emitOpened({'route': 'chat', 'match_id': _roomId});
      await tester.pumpAndSettle();

      expect(find.byType(ChatRoomScreen, skipOffstage: false), findsNothing);
      expectSingleWaitingHome(tester);
    });

    testStill('꺼진 앱을 알림으로 켜도 요약이 오면 홈 한 장에 선다', (tester) async {
      await pumpHome(tester, summary: waiting, launch: {'route': 'heart_tasks', 'task': 'everytime_post'});

      expect(find.byType(HeartTasksScreen, skipOffstage: false), findsNothing);
      expectSingleWaitingHome(tester);
    });

    // 채팅 · 대화 목록 알림은 홈을 깔지 않고 바로 연다(PushRoute._staysAlone) — 그 화면은 홈 요약을 안 읽어
    // 대기인지 끝까지 모른 채 잠금이 풀렸다(검토 FAIL 11-11). 알림을 여는 순간 요약 읽기를 시작해야 한다.
    for (final (name, data) in [
      ('채팅', {'route': 'chat', 'match_id': _roomId}),
      ('받은 수락', {'route': 'acceptances'}),
      ('매칭', {'route': 'match', 'match_id': _roomId}),
    ]) {
      testStill('꺼진 앱을 $name 알림으로 켜도 요약이 오면 홈 한 장에 선다', (tester) async {
        await pumpHome(tester, summary: waiting, launch: data);

        expect(find.byType(ChatRoomScreen, skipOffstage: false), findsNothing);
        expect(find.byType(ConversationsScreen, skipOffstage: false), findsNothing);
        expectSingleWaitingHome(tester);
      });
    }

    // 막힌 탭 위에 설정(열린 곳)을 쌓은 채 대기로 바뀌면 맨 위만 보는 [_leaveBlockedScreen] 은 못 잡는다 —
    // 라우터 새로 고침(refreshListenable 의 대기 신호)이 맨 아래 막힌 경로를 홈으로 바꿔야 한다.
    testStill('대화 탭 위에 설정을 연 채 요약이 대기로 바뀌면 대화 탭이 밑에 남지 않는다', (tester) async {
      final (_, push) = await pumpHome(tester);
      push.emitOpened({'route': 'acceptances'});
      await tester.pumpAndSettle();
      expect(find.byType(ConversationsScreen), findsOneWidget);
      unawaited(GoRouter.of(tester.element(find.byType(ConversationsScreen))).push(AppRoutes.settings));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      appHome.summary = waiting;
      appContainer.invalidate(homeSummaryProvider);
      await tester.pumpAndSettle();

      expect(find.byType(ConversationsScreen, skipOffstage: false), findsNothing);
    });
  });

  // iOS 는 FCM 표시 옵션이 시스템 배너를 띄운다 — 앱이 또 띄우면 같은 알림이 두 번 뜬다.
  testWidgets(
    'iOS 에서는 FCM 포그라운드 표시를 켜고 앱이 직접 알림을 띄우지 않는다',
    (tester) async {
      final (_, push) = await pumpHome(tester);

      push.emitMessage({'route': 'acceptances'}, title: '대화 신청이 왔어요', body: '본문');
      await tester.pumpAndSettle();

      expect(push.presentWhileOpenCalls, 1);
      expect(appSystemNotifications.initializeCalls, 0);
      expect(appSystemNotifications.shown, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('로그아웃한 직후 푸시가 와도 안 읽은 알림 수를 읽지 않는다', (tester) async {
    final (_, push) = await pumpHome(tester);
    final before = appNotifications.countCalls;
    await tester.runAsync(() async {
      try {
        await auth().signOut();
      } on AuthException {
        // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
      }
    });

    push.emitMessage({'route': 'acceptances'});
    await tester.pump(const Duration(milliseconds: 100));

    expect(appNotifications.countCalls, before);
  });

  // 채팅 실시간 전환 설계안 A 4단계 — 앱이 앞에 있는 동안 로그인 · 관문 통과한 사람의 `user:<내 id>` 하나를 듣는다.
  group('사용자 채널', () {
    testWidgets('관문이 열린 사람은 내 id 로 채널을 하나 연다', (tester) async {
      await pumpHome(tester);

      expect(appEvents.subscribed, ['u1']);
      expect(appEvents.openCount, 1);
    });

    testWidgets('관문이 안 끝난 사람은 채널을 열지 않는다', (tester) async {
      await pumpGatedApp(tester);

      expect(appEvents.subscribed, isEmpty);
    });

    testWidgets('붙으면 연결됨이 되고, 홈 탭에 있어도 상대 메시지가 오면 하단 내비 대화 숫자가 바로 바뀐다', (tester) async {
      final (chat, _) = await pumpHome(tester);
      chat.conversations = Success([conversationWith('새연결')]);
      appEvents.connect();
      await tester.pumpAndSettle();
      expect(appContainer.read(userChannelProvider), isTrue);
      expect(appContainer.read(chatBadgeCountProvider), 0);

      appEvents.push(MessageEvent(
        _roomId,
        Message(id: 'msg-rt', senderId: 'p1', body: '지금 왔어요', kind: MessageKind.text, createdAt: DateTime(2026, 10, 6)),
      ));
      await tester.pumpAndSettle();

      expect(appContainer.read(chatBadgeCountProvider), 1);
      expect(find.descendant(of: find.byType(GlassBottomNav), matching: find.text('1')), findsOneWidget);
    });

    testWidgets('앱이 뒤로 가면 채널을 닫고, 앞으로 오면 다시 열어 붙은 뒤 목록을 한 번 더 읽는다', (tester) async {
      final (chat, _) = await pumpHome(tester);
      appEvents.connect();
      await tester.pumpAndSettle();

      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect((appEvents.openCount, appContainer.read(userChannelProvider)), (0, false));

      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      auth().stopAutoRefresh();
      expect(appEvents.subscribed, ['u1', 'u1']);
      expect(appEvents.openCount, 1);
      final before = chat.conversationsFetchCount;

      appEvents.connect();
      await tester.pumpAndSettle();

      expect(chat.conversationsFetchCount, before + 1);
      expect(appContainer.read(userChannelProvider), isTrue);
    });

    testWidgets('로그아웃하면 채널을 닫는다', (tester) async {
      await pumpHome(tester);
      appEvents.connect();
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        try {
          await auth().signOut();
        } on AuthException {
          // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
        }
      });
      await tester.pump();

      expect(appEvents.openCount, 0);
    });
  });

  // 사용 통계 push_open — 푸시를 눌러 앱이 열리거나 이동할 때, 종류값(data.route)만 남긴다. 방 id · 상대 id 등 data 의 나머지는 싣지 않는다.
  group('푸시 열기 분석(push_open)', () {
    List<String> opens() => appAnalytics.calls.where((call) => call.startsWith('push_open')).toList();

    testWidgets('백그라운드의 앱을 알림으로 열면 종류값을 남긴다', (tester) async {
      final (_, push) = await pumpHome(tester);

      push.emitOpened({'route': 'match', 'match_id': _roomId});
      await tester.pumpAndSettle();

      expect(opens(), ['push_open:match']);
      expect(appAnalytics.calls.join(), isNot(contains(_roomId)));
    });

    testWidgets('꺼진 앱을 앱이 띄운 알림으로 켜도 남긴다', (tester) async {
      await pumpHome(tester, launch: {'route': 'chat', 'match_id': _roomId});

      expect(opens(), ['push_open:chat']);
    });

    testWidgets('모르는 종류(옛 학생증 결과 등)는 other 로 남긴다', (tester) async {
      final (_, push) = await pumpHome(tester);

      push.emitOpened({'route': 'verification', 'extra': '홍길동'});
      await tester.pumpAndSettle();

      expect(opens(), ['push_open:other']);
    });

    testWidgets('앱이 켜진 채 받기만 한 알림은 열기가 아니라서 남기지 않는다', (tester) async {
      final (_, push) = await pumpHome(tester);

      push.emitMessage({'route': 'daily_card'}, title: '새 카드', body: '도착했어요');
      await tester.pumpAndSettle();

      expect(opens(), isEmpty);
    });
  });

}
