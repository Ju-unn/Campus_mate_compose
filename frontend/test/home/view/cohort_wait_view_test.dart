import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/cohort_wait.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/referral/model/referral_repository.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../referral/model/fake_referral_repository.dart';
import '../model/fake_home_repository.dart';

/// 코드를 바로 주지 않는 추천 저장소 — 기다리는 동안 두 번 누르기를 본다.
class _SlowReferralRepository extends FakeReferralRepository {
  final gate = Completer<Result<String>>();
  int calls = 0;

  @override
  Future<Result<String>> myCode() {
    calls++;
    return gate.future;
  }
}

/// 19 코호트 대기(pen `tUaGw`). 값은 계획서 2026-09-28-cohort-wait.md 화면 대조표.
void main() {
  // 기기 시간대 기준. 여는 날은 월요일 07:00(계획서 결정 2).
  final opensAt = DateTime(2099, 9, 21, 7);

  group('글 — 달력 날짜로 센다(결정 8 · Q1 (가))', () {
    test('14일 전이면 "D-14" 와 날짜', () {
      final now = DateTime(2099, 9, 7, 12);
      expect(cohortDayLabel(now, opensAt), 'D-14');
      expect(cohortDateLabel(now, opensAt), '9월 21일');
    });

    test('전날 23:59 는 "D-1" — 시각 차이(7시간)가 아니라 날짜 차이다', () {
      expect(cohortDayLabel(DateTime(2099, 9, 20, 23, 59), opensAt), 'D-1');
    });

    test('당일 06:59 는 "D-day" 와 "오늘 오전 7시"', () {
      final now = DateTime(2099, 9, 21, 6, 59);
      expect(cohortDayLabel(now, opensAt), 'D-day');
      expect(cohortDateLabel(now, opensAt), '오늘 오전 7시');
    });

    test('여는 시각이 지나도 "D-day" — 음수로 가지 않는다', () {
      expect(cohortDayLabel(DateTime(2099, 9, 22, 8), opensAt), 'D-day');
    });

    test('시각은 7 을 박지 않고 여는 시각에서 읽는다', () {
      final now = DateTime(2099, 9, 21, 6);
      expect(cohortDateLabel(now, DateTime(2099, 9, 21, 13, 30)), '오늘 오후 1시 30분');
      expect(cohortDateLabel(now, DateTime(2099, 9, 21, 12)), '오늘 오후 12시');
    });
  });

  late FakeHomeRepository repository;
  late DateTime now;
  late ReferralRepository referral;
  late List<String> shared;
  late Future<void> Function(String) share;

  setUp(() {
    referral = FakeReferralRepository();
    shared = [];
    share = (text) async => shared.add(text);
  });

  HomeSummary summaryWith(CohortWait? cohort) => HomeSummary(
    presentPeopleImages: const ['assets/images/person-f1-blind-v1.png'],
    deliveredCards: 10,
    signups: 20,
    conversationsStarted: 3,
    reviewRating: 4.8,
    reviewCount: 143,
    campuses: const ['가람대'],
    profileCompletionPercent: 60,
    cohort: cohort,
  );

  Future<void> pump(WidgetTester tester, {DateTime? firstCardAt, int recruitCount = 87}) async {
    repository = FakeHomeRepository(
      Success(summaryWith(CohortWait(firstCardAt: firstCardAt ?? opensAt, recruitCount: recruitCount))),
    );
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repository),
        homeNowProvider.overrideWithValue(() => now),
        referralRepositoryProvider.overrideWithValue(referral),
        shareTextProvider.overrideWithValue((text) => share(text)),
        // 하단 내비 뱃지가 수락 대기·안 읽은 메시지를 읽는다(§8.8).
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
  }

  group('친구 초대(A4 · 결정 5)', () {
    Future<void> tapInvite(WidgetTester tester) async {
      // 기본 테스트 화면(800×600)에선 버튼이 접힌 곳 아래라 먼저 스크롤한다.
      await tester.ensureVisible(find.text('친구에게 초대 링크 보내기'));
      await tester.pump();
      await tester.tap(find.text('친구에게 초대 링크 보내기'));
      await tester.pump();
    }

    testWidgets('누르면 내 추천 코드를 넣은 글로 휴대폰 공유 창을 연다', (tester) async {
      now = DateTime(2099, 9, 7, 12);
      await pump(tester);

      await tapInvite(tester);

      expect(shared, ['CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘.']);
    });

    testWidgets('코드를 못 받으면 공유하지 않고 실패 문구를 토스트로 보인다. 화면은 그대로', (tester) async {
      now = DateTime(2099, 9, 7, 12);
      referral = FakeReferralRepository()..nextMyCode = const FailureResult(NetworkFailure());
      await pump(tester);

      await tapInvite(tester);

      expect(shared, isEmpty);
      expect(find.text(const NetworkFailure().toDisplayMessage()), findsOneWidget);
      expect(find.byType(AppToast), findsOneWidget);
      expect(find.text('친구에게 초대 링크 보내기'), findsOneWidget);
    });

    testWidgets('코드를 기다리는 동안 한 번 더 눌러도 공유는 한 번', (tester) async {
      now = DateTime(2099, 9, 7, 12);
      final slow = _SlowReferralRepository();
      referral = slow;
      await pump(tester);

      await tapInvite(tester);
      await tapInvite(tester);
      slow.gate.complete(const Success('K7QMX2'));
      await tester.pump();

      expect(slow.calls, 1);
      expect(shared, hasLength(1));
    });

    testWidgets('공유 창을 못 열면 조용히 끝나지 않고 토스트로 알린다', (tester) async {
      now = DateTime(2099, 9, 7, 12);
      share = (_) async => throw Exception('공유 창 없음');
      await pump(tester);

      await tapInvite(tester);

      expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
    });
  });

  testWidgets('pen 19 글이 다 있고 "첫 100명 모집 중" 배지는 없다(Q3 (가))', (tester) async {
    now = DateTime(2099, 9, 7, 12);
    await pump(tester);

    expect(find.byType(CohortWaitView), findsOneWidget);
    expect(find.text('우리 학교 첫 카드까지 · D-14'), findsOneWidget);
    expect(find.text('9월 21일'), findsOneWidget);
    expect(find.text('같은 날, 같은 설렘으로 시작해요'), findsOneWidget);
    expect(find.text('현재 모집 인원'), findsOneWidget);
    expect(find.text('87명'), findsOneWidget);
    expect(find.text('친구와 함께 시작하면 첫날부터 더 많은 캠퍼스 친구를 만날 수 있어요.'), findsOneWidget);
    expect(find.text('친구에게 초대 링크 보내기'), findsOneWidget);
    expect(find.textContaining('100명'), findsNothing);
  });

  testWidgets('pen 값 — 히어로 330 · 모집 판 92 · 버튼 52 가 내비 위 24 에 붙는다(360×800)', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    now = DateTime(2099, 9, 7, 12);
    await pump(tester);

    final mascot = find.byType(Image).first;
    expect(tester.getSize(mascot), const Size(132, 132));
    expect((tester.widget<Image>(mascot).image as AssetImage).assetName, 'assets/images/mascot-male.png');
    // `gFbj2` 는 앱바 56 + 위 8 에서 시작해 330, 안쪽 위 20 에 마스코트.
    final hero = find.ancestor(of: mascot, matching: find.byType(Container)).first;
    expect(tester.getRect(hero), const Rect.fromLTWH(16, 64, 328, 330));
    expect(tester.getTopLeft(mascot).dy, 84);
    final panel = find.ancestor(of: find.text('87명'), matching: find.byType(Container)).first;
    expect(tester.getRect(panel), const Rect.fromLTWH(16, 414, 328, 92));
    final button = find.ancestor(of: find.text('친구에게 초대 링크 보내기'), matching: find.byType(ElevatedButton));
    expect(tester.getSize(button), const Size(328, 52));
    expect(tester.getTopLeft(find.byType(AppBottomNav)).dy - tester.getBottomLeft(button).dy, 24);
  });

  testWidgets('pen 값 — 큰 날짜 `IDJ3M` 은 countdown 이 아닌 48/700 lh1.5 자간 0 · 모집 판 두 줄은 lh1.5 사이 4', (tester) async {
    now = DateTime(2099, 9, 7, 12);
    await pump(tester);

    final date = tester.widget<Text>(find.text('9월 21일')).style!;
    expect(date.fontSize, 48);
    expect(date.fontWeight, FontWeight.w700);
    expect(date.height, 1.5);
    expect(date.letterSpacing, 0);
    // `WEPFQ` 14 · `ebHk4` 24 둘 다 lh1.5, 사이는 왼쪽 열 `o6UY45` gap 4. 판 92 는 위 테스트가 본다.
    final label = find.text('현재 모집 인원');
    final count = find.text('87명');
    expect(tester.getSize(label).height, 21);
    expect(tester.getSize(count).height, 36);
    expect(tester.getTopLeft(count).dy - tester.getBottomLeft(label).dy, 4);
  });

  testWidgets('여는 시각이 되면 요약을 다시 읽는다', (tester) async {
    now = opensAt.subtract(const Duration(seconds: 5));
    await pump(tester);
    expect(repository.calls, 1);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(repository.calls, 1);

    now = opensAt;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repository.calls, 2);
  });

  testWidgets('자정을 넘기면 껐다 켜지 않아도 D-숫자가 바뀐다', (tester) async {
    now = DateTime(2099, 9, 12, 23, 59, 50);
    await pump(tester);
    expect(find.text('우리 학교 첫 카드까지 · D-9'), findsOneWidget);

    now = DateTime(2099, 9, 13);
    await tester.pump(const Duration(seconds: 10));

    expect(find.text('우리 학교 첫 카드까지 · D-8'), findsOneWidget);
    expect(repository.calls, 1, reason: '자정에는 요약을 다시 읽지 않는다');
  });

  group('폰이 잠든 사이 타이머가 안 울렸어도 앱으로 돌아오면 다시 센다', () {
    // 잠든 시간은 타이머 시계에 안 잡힐 수 있다 — 시각만 옮기고 타이머는 돌리지 않는다.
    // AppLifecycleListener 는 한 칸씩 넘어가는 순서만 받는다 — 기기와 같은 순서로 보낸다.
    Future<void> sleepAndResume(WidgetTester tester) async {
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
      await tester.pump();
    }

    testWidgets('자정을 넘겨 돌아오면 D-숫자가 바뀌고 요약은 다시 읽지 않는다', (tester) async {
      now = DateTime(2099, 9, 20, 23);
      await pump(tester);
      expect(find.text('우리 학교 첫 카드까지 · D-1'), findsOneWidget);

      now = DateTime(2099, 9, 21, 6, 30);
      await sleepAndResume(tester);

      expect(find.text('우리 학교 첫 카드까지 · D-day'), findsOneWidget);
      expect(find.text('오늘 오전 7시'), findsOneWidget);
      expect(repository.calls, 1);
    });

    testWidgets('여는 시각을 지나 돌아오면 바로 요약을 다시 읽는다', (tester) async {
      now = DateTime(2099, 9, 20, 23);
      await pump(tester);

      now = DateTime(2099, 9, 21, 7, 30);
      await sleepAndResume(tester);

      expect(repository.calls, 2);
    });
  });

  testWidgets('다시 읽은 요약이 다른 여는 시각을 가져오면 그 시각에 맞춰 다시 건다', (tester) async {
    now = DateTime(2099, 9, 7, 12);
    await pump(tester);

    // 운영자가 여는 날짜를 앞당겼다(5초 뒤). 다음 자정(12시간 뒤) 타이머만 남아 있으면 못 연다.
    final soon = now.add(const Duration(seconds: 5));
    repository.summary = Success(summaryWith(CohortWait(firstCardAt: soon, recruitCount: 87)));
    ProviderScope.containerOf(tester.element(find.byType(CohortWaitView))).invalidate(homeSummaryProvider);
    await tester.pump(); // 다시 읽기
    await tester.pump(); // 새 요약으로 다시 그림 → didUpdateWidget
    expect(repository.calls, 2);

    now = soon;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(repository.calls, 3);
  });

  testWidgets('기기 시계가 빨라 지난 시각인데도 cohort 가 오면 1분 뒤에만 다시 읽는다', (tester) async {
    now = opensAt.add(const Duration(seconds: 1));
    await pump(tester);
    expect(repository.calls, 1);

    await tester.pump(const Duration(seconds: 59));
    await tester.pump();
    expect(repository.calls, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repository.calls, 2);

    // 또 cohort 가 오면 다시 1분을 기다린다 — 0초로 되풀이하지 않는다.
    await tester.pump(const Duration(seconds: 59));
    await tester.pump();
    expect(repository.calls, 2);
  });

  for (final (label, firstCardAt, clock) in [
    ('12월 27일', DateTime(2099, 12, 27, 7), DateTime(2099, 12, 1, 12)),
    ('오늘 오전 7시', DateTime(2099, 12, 27, 7), DateTime(2099, 12, 27, 6)),
  ]) {
    testWidgets('글자 1.3배 · 360×640 에서 "$label" 이 넘치지 않고 버튼까지 스크롤로 닿는다', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      now = clock;

      await pump(tester, firstCardAt: firstCardAt, recruitCount: 1234);
      expect(find.text(label), findsOneWidget);
      await tester.scrollUntilVisible(find.text('친구에게 초대 링크 보내기'), 100, scrollable: find.byType(Scrollable).first);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text(label)).width, lessThanOrEqualTo(288), reason: '히어로 안쪽 폭 328 − 40');
    });
  }
}
