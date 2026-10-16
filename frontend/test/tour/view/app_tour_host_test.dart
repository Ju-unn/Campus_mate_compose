import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/tour/model/tour_seen_store.dart';
import 'package:campus_mate/tour/view/app_tour_host.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/coach_bubble.dart';
import 'package:campus_mate/tour/view/coach_line.dart';
import 'package:campus_mate/tour/view/coach_overlay.dart';
import 'package:campus_mate/tour/view/tour_target.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_tour_seen_store.dart';

const _hero = ValueKey('hero');
const _nudge = ValueKey('nudge');
const _under = ValueKey('under');
const _tabs = ValueKey('tabs');
const _arrival = ValueKey('arrival');
const _header = ValueKey('header');
const _free = ValueKey('free');
const _bar = ValueKey('bar');

/// pen 구멍 띄움(campus-pen 확인) — 탭 줄 묶음 · 글자 영역.
Rect _tabsHole(Rect rect) => const EdgeInsets.fromLTRB(8, 4, 8, 6).inflateRect(rect);
Rect _textHole(Rect rect) => const EdgeInsets.symmetric(vertical: 7, horizontal: 38).inflateRect(rect);

/// jumpTo 를 센다 — 목록을 끝으로 미는 횟수.
class _CountingController extends ScrollController {
  int jumps = 0;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _CountingPosition(this, physics: physics, context: context, oldPosition: oldPosition);
}

class _CountingPosition extends ScrollPositionWithSingleContext {
  _CountingPosition(this.owner, {required super.physics, required super.context, super.oldPosition});

  final _CountingController owner;

  @override
  void jumpTo(double value) {
    owner.jumps++;
    super.jumpTo(value);
  }
}

/// 진짜 화면 대신 같은 대상 id 를 단 가벼운 화면들 — 호스트의 이동 · 찾기 · 그리기만 본다(진짜 화면에 단 자리는 각 화면 시험).
/// 홈의 완성도 카드는 목록 끝(화면 밖, 아직 안 만들어짐)이라 2단계가 스크롤해 찾아야 한다.
class _Pages {
  _Pages({this.nudge = true, this.arrival = true, this.longHome = false, this.freeHeight = 200, this.heartBar = 0});

  final bool nudge;
  final bool arrival;

  /// 하트 스토어 "무료로 모으기" 묶음 높이와 하단 구매 바 높이(0 이면 바 없음).
  final double freeHeight;
  final double heartBar;

  /// 홈 목록이 아직 길어지는 중(늦게 받는 내용)이고 맨 위 손잡이가 계속 만들어져 있는 경우 — 완성도 카드는 없다.
  final bool longHome;
  final scroll = _CountingController();

  /// 켜면 그때부터 2초 동안 목록이 길어진다(늦게 받는 내용).
  final grow = ValueNotifier<bool>(false);
  final heroHeight = ValueNotifier<double>(160);
  int underTaps = 0;

  List<RouteBase> routes() => [
        GoRoute(path: AppRoutes.home, builder: (context, state) => _home()),
        GoRoute(
          path: AppRoutes.community,
          builder: (context, state) => Scaffold(
            appBar: AppBar(
              title: const Text('커뮤니티'),
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(102),
                child: TourTarget(id: TourTargetId.communityTabs, child: SizedBox(key: _tabs, width: 328, height: 86)),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.today,
          builder: (context, state) => Scaffold(
            appBar: AppBar(
              title: const TourTarget(id: TourTargetId.todayHeader, child: Text('오늘의 카드', key: _header)),
            ),
            body: Center(
              child: arrival
                  ? const TourTarget(id: TourTargetId.todayArrival, child: SizedBox(key: _arrival, width: 240, height: 100))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.heartStore,
          // 진짜 상점처럼 앱바 56 · 목록 안쪽 [8,16,32,16] · (있으면) 하단 구매 바 · 목록 끝 빈자리(TourScrollRoom).
          builder: (context, state) => Scaffold(
            appBar: AppBar(title: const Text('하트')),
            bottomNavigationBar: heartBar > 0 ? SizedBox(key: _bar, height: heartBar) : null,
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const TourTarget(id: TourTargetId.heartStoreTop, child: SizedBox(height: 180)),
                for (var i = 0; i < 8; i++) const SizedBox(height: 120),
                TourTarget(id: TourTargetId.heartStoreFree, child: SizedBox(key: _free, height: freeHeight)),
                const TourScrollRoom(id: TourTargetId.heartStoreFree),
              ],
            ),
          ),
        ),
        GoRoute(path: AppRoutes.settings, builder: (context, state) => const Scaffold(body: Center(child: Text('설정')))),
      ];

  Widget _home() => longHome ? _longHome() : _shortHome();

  Widget _longHome() => Scaffold(
        body: ListView(
          controller: scroll,
          // 손잡이(히어로)가 화면 밖으로 밀려도 만들어진 채 남게 한다.
          scrollCacheExtent: const ScrollCacheExtent.pixels(100000),
          children: [
            const TourTarget(id: TourTargetId.homeHero, child: SizedBox(key: _hero, height: 160)),
            ValueListenableBuilder<bool>(
              valueListenable: grow,
              builder: (context, growing, _) => growing
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: 800, end: 4000),
                      duration: const Duration(seconds: 2),
                      builder: (context, height, _) => SizedBox(height: height),
                    )
                  : const SizedBox(height: 800),
            ),
          ],
        ),
      );

  Widget _shortHome() => Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TourTarget(
              id: TourTargetId.homeHero,
              child: ValueListenableBuilder<double>(
                valueListenable: heroHeight,
                builder: (context, height, _) => SizedBox(key: _hero, height: height),
              ),
            ),
            ElevatedButton(key: _under, onPressed: () => underTaps++, child: const Text('밑 버튼')),
            const SizedBox(height: 900),
            if (nudge) const TourTarget(id: TourTargetId.homeProfileNudge, child: SizedBox(key: _nudge, height: 92)),
          ],
        ),
      );
}

void main() {
  late ProviderContainer container;
  late GoRouter router;
  late _Pages pages;

  Future<void> pump(
    WidgetTester tester, {
    bool nudge = true,
    bool arrival = true,
    bool longHome = false,
    String initial = AppRoutes.home,
    Size size = const Size(360, 740),
    double freeHeight = 200,
    double heartBar = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    pages = _Pages(nudge: nudge, arrival: arrival, longHome: longHome, freeHeight: freeHeight, heartBar: heartBar);
    addTearDown(pages.scroll.dispose);
    container = ProviderContainer(
      overrides: [
        tourSeenStoreProvider.overrideWithValue(FakeTourSeenStore()),
        tourAccountIdProvider.overrideWithValue(() => 'profile-a'),
      ],
    );
    addTearDown(container.dispose);
    router = GoRouter(initialLocation: initial, routes: pages.routes());
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppTourHost(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    container.read(appTourViewModelProvider.notifier).replay();
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.descendant(of: find.byType(CoachBubble), matching: find.byType(AppButton)));
    await tester.pumpAndSettle();
  }

  CoachOverlay overlay(WidgetTester tester) => tester.widget<CoachOverlay>(find.byType(CoachOverlay));
  Rect rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));
  Finder inBubble(String text) => find.descendant(of: find.byType(CoachBubble), matching: find.text(text));
  String location() => router.state.matchedLocation;
  double overlayOpacity(WidgetTester tester) =>
      tester.widget<FadeTransition>(find.byKey(const ValueKey('app-tour-overlay'))).opacity.value;

  testWidgets('시작 → 1단계: 홈 히어로를 2 띄운 구멍(반경 34)으로 두르고, 52 아래(점 10 + 선 42)에 폭 312 말풍선 "1 / 6"', (tester) async {
    await pump(tester);
    await start(tester);

    expect(overlay(tester).hole, rectOf(tester, _hero).inflate(2));
    expect(overlay(tester).radius, 34);
    expect(inBubble('1 / 6'), findsOneWidget);
    expect(inBubble('여기가 캠퍼스메이트의 시작이에요'), findsOneWidget);
    expect(inBubble('오늘의 카드와 소중한 인연을 만나봐요.'), findsOneWidget);
    final bubble = tester.getRect(find.byType(CoachBubble));
    expect(bubble.width, 312);
    expect(bubble.left, (360 - 312) / 2);
    expect(bubble.top, overlay(tester).hole!.bottom + 52);
    final line = tester.getRect(find.byType(CoachLine));
    expect((line.top, line.bottom), (overlay(tester).hole!.bottom, bubble.top));
  });

  testWidgets('다음을 누르면 실제 화면을 옮겨 가며 6단계를 잇고, "시작하기" 로 끝나 홈으로 돌아온다', (tester) async {
    await pump(tester);
    await start(tester);
    final skipSlot = tester.getSize(find.byKey(CoachBubble.skipKey));

    // 2 — 완성도 카드: 목록 끝이라 스크롤해 찾는다. 화면 아래쪽이라 말풍선은 위.
    await next(tester);
    expect(location(), AppRoutes.home);
    expect(inBubble('2 / 6'), findsOneWidget);
    expect(overlay(tester).hole, rectOf(tester, _nudge).inflate(2));
    expect(overlay(tester).radius, 26);
    expect(tester.getRect(find.byType(CoachBubble)).bottom, overlay(tester).hole!.top - 52);

    // 3 — 커뮤니티 탭으로 옮겨 탭 줄.
    await next(tester);
    expect(location(), AppRoutes.community);
    expect(inBubble('3 / 6'), findsOneWidget);
    expect(overlay(tester).hole, _tabsHole(rectOf(tester, _tabs)));
    expect(overlay(tester).radius, 16);

    // 4 — 오늘 탭 도착 시각.
    await next(tester);
    expect(location(), AppRoutes.today);
    expect(inBubble('4 / 6'), findsOneWidget);
    expect(overlay(tester).hole, _textHole(rectOf(tester, _arrival)));

    // 5 — 같은 화면, 구멍 없이 가운데 설명 카드 + 정밀 분석 항목 넷.
    await next(tester);
    expect(location(), AppRoutes.today);
    expect(inBubble('5 / 6'), findsOneWidget);
    expect(overlay(tester).hole, isNull);
    expect(find.byType(CoachLine), findsNothing);
    for (final item in ['성향 9가지 비교', '관심사와 특징 태그', 'AI 글 분석', '원하는 조건 반영']) {
      expect(inBubble(item), findsOneWidget);
    }
    expect(tester.getCenter(find.byType(CoachBubble)).dy, closeTo(740 / 2, 1));

    // 6 — 하트 스토어를 위에 올려 끝의 무료로 모으기까지 스크롤. 마지막 장은 "시작하기", 건너뛰기는 자리만.
    await next(tester);
    expect(location(), AppRoutes.heartStore);
    expect(inBubble('6 / 6'), findsOneWidget);
    expect(overlay(tester).hole, rectOf(tester, _free).inflate(4));
    expect(find.widgetWithText(AppButton, '시작하기'), findsOneWidget);
    expect(find.text('건너뛰기').hitTestable(), findsNothing);
    expect(tester.getSize(find.byKey(CoachBubble.skipKey)), skipSlot);

    await next(tester);
    expect(find.byType(CoachOverlay), findsNothing);
    expect(container.read(appTourViewModelProvider).active, isFalse);
    expect(location(), AppRoutes.home);
  });

  testWidgets('건너뛰기 → 그 자리에서 바로 끝나고 화면은 옮기지 않는다', (tester) async {
    await pump(tester);
    await start(tester);
    await next(tester);
    await next(tester);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(find.byType(CoachOverlay), findsNothing);
    expect(container.read(appTourViewModelProvider).active, isFalse);
    expect(location(), AppRoutes.community);
  });

  testWidgets('시스템 뒤로가기 = 건너뛰기 — 6단계 상점에서 눌러도 상점은 닫히지 않고 투어만 끝난다, 끝난 뒤에는 평소대로 닫힌다', (tester) async {
    await pump(tester);
    await start(tester);
    for (var i = 0; i < 5; i++) {
      await next(tester);
    }
    expect(location(), AppRoutes.heartStore);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(CoachOverlay), findsNothing);
    expect(location(), AppRoutes.heartStore);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(location(), AppRoutes.today);
  });

  testWidgets('대상을 끝내 못 찾으면 그 단계를 건너뛰고 "n / 총" 을 다시 센다 — 완성도 카드가 없으면 커뮤니티가 "2 / 5"', (tester) async {
    await pump(tester, nudge: false);
    await start(tester);

    await next(tester);

    expect(location(), AppRoutes.community);
    expect(inBubble('2 / 5'), findsOneWidget);
    expect(overlay(tester).hole, _tabsHole(rectOf(tester, _tabs)));
  });

  testWidgets('오늘 탭에 도착 시각 안내가 없으면(카드 목록 등) 앱바 제목(상단 영역)을 가리킨다', (tester) async {
    await pump(tester, arrival: false);
    await start(tester);
    for (var i = 0; i < 3; i++) {
      await next(tester);
    }

    expect(inBubble('4 / 6'), findsOneWidget);
    expect(overlay(tester).hole, _textHole(rectOf(tester, _header)));
  });

  testWidgets('다른 화면(설정)에서 다시 보기를 부르면 홈으로 옮긴 뒤 1단계를 보인다', (tester) async {
    await pump(tester, initial: AppRoutes.settings);
    await start(tester);

    expect(location(), AppRoutes.home);
    expect(inBubble('1 / 6'), findsOneWidget);
  });

  testWidgets('투어 중에는 덮개 밖을 눌러도 밑 화면이 반응하지 않고, 끝나면 다시 눌린다', (tester) async {
    await pump(tester);
    await start(tester);

    await tester.tapAt(tester.getCenter(find.byKey(_under)));
    await tester.pumpAndSettle();
    expect(pages.underTaps, 0);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_under));
    expect(pages.underTaps, 1);
  });

  testWidgets('대상 자리가 바뀌면(늦게 그려짐 · 회전 · 키보드) 다음 프레임에 구멍과 말풍선이 따라간다', (tester) async {
    await pump(tester);
    await start(tester);

    pages.heroHeight.value = 220;
    await tester.pumpAndSettle();
    expect(overlay(tester).hole, rectOf(tester, _hero).inflate(2));
    expect(tester.getRect(find.byType(CoachBubble)).top, overlay(tester).hole!.bottom + 52);

    tester.view.physicalSize = const Size(740, 360);
    await tester.pumpAndSettle();
    expect(overlay(tester).hole, rectOf(tester, _hero).inflate(2));
    expect(tester.getRect(find.byType(CoachBubble)).left, (740 - 312) / 2);
  });

  testWidgets('구멍이 움직이는 중에 다음을 또 눌러도 그 자리에서 이어 다음 대상으로 간다', (tester) async {
    await pump(tester);
    await start(tester);
    await next(tester);

    await tester.tap(find.descendant(of: find.byType(CoachBubble), matching: find.byType(AppButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.descendant(of: find.byType(CoachBubble), matching: find.byType(AppButton)));
    await tester.pumpAndSettle();

    expect(inBubble('4 / 6'), findsOneWidget);
    expect(overlay(tester).hole, _textHole(rectOf(tester, _arrival)));
  });

  testWidgets('대상 없는 5단계(가운데 카드)에서 다른 길(알림 · 로그아웃 · 딥링크)로 화면이 바뀌어도 빈 덮개를 남기지 않고 끝낸다', (tester) async {
    await pump(tester);
    await start(tester);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    expect(inBubble('5 / 6'), findsOneWidget);

    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();

    expect(find.byType(CoachOverlay), findsNothing);
    expect(container.read(appTourViewModelProvider).active, isFalse);
  });

  testWidgets('목록 끝 대상을 찾을 때 목록은 한 번만 끝으로 민다 — 끝내 없으면 그 단계를 건너뛰고 다시 센다', (tester) async {
    await pump(tester, longHome: true);
    await start(tester);
    pages.grow.value = true;
    final before = pages.scroll.jumps;

    await next(tester);

    expect(pages.scroll.jumps - before, 1);
    expect(location(), AppRoutes.community);
    expect(inBubble('2 / 5'), findsOneWidget);
  });

  testWidgets('투어 중 다른 길(알림 누름 등)로 대상이 사라지면 빈 덮개를 남기지 않고 끝낸다', (tester) async {
    await pump(tester);
    await start(tester);

    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();

    expect(find.byType(CoachOverlay), findsNothing);
    expect(container.read(appTourViewModelProvider).active, isFalse);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 로 6단계를 다 돌아도 넘침 · 화면 밖 말풍선이 없다(모자라면 말풍선 안이 스크롤)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
      await start(tester);

      for (var step = 1; step <= 6; step++) {
        expect(inBubble('$step / 6'), findsOneWidget, reason: '$step단계');
        expect(tester.takeException(), isNull, reason: '$step단계');
        final bubble = tester.getRect(find.byType(CoachBubble).hitTestable());
        expect(bubble.top, greaterThanOrEqualTo(0), reason: '$step단계');
        if (step == 5) {
          // 5단계(가운데 카드)는 글자 2배면 화면보다 길다 — 스크롤 칸은 화면 안이고, 내리면 "다음" 이 보이고 눌린다.
          final room = tester.getRect(
            find.ancestor(of: find.byType(CoachBubble), matching: find.byType(SingleChildScrollView)),
          );
          expect(room.top, greaterThanOrEqualTo(0), reason: '$step단계');
          expect(room.bottom, lessThanOrEqualTo(740), reason: '$step단계');
          final nextButton = find.descendant(of: find.byType(CoachBubble), matching: find.byType(AppButton));
          await tester.ensureVisible(nextButton);
          await tester.pumpAndSettle();
          expect(nextButton.hitTestable(), findsOneWidget, reason: '$step단계');
          expect(tester.getRect(nextButton).bottom, lessThanOrEqualTo(room.bottom), reason: '$step단계');
        } else {
          expect(bubble.bottom, lessThanOrEqualTo(740), reason: '$step단계');
        }
        if (step < 6) await next(tester);
      }
    });
  }

  group('긴 대상 · 작은 화면 — 구멍은 보이는 영역 안, 말풍선은 화면 안', () {
    Future<void> toLastStep(WidgetTester tester) async {
      await start(tester);
      for (var i = 0; i < 5; i++) {
        await next(tester);
      }
    }

    /// 말풍선이 잘리지 않았다 — 말풍선을 품은 스크롤이 더 밀리지 않는다.
    bool bubbleWhole(WidgetTester tester) {
      final scroll = find.ancestor(of: find.byType(CoachBubble), matching: find.byType(Scrollable)).first;
      return tester.state<ScrollableState>(scroll).position.maxScrollExtent == 0;
    }

    testWidgets('6단계 pen 값(360×780) — 무료로 모으기를 앱바 아래 12 로 올려 구멍 x12 · y68 · 336×306 · 반경 16, 아래 선 52 · 말풍선 x24 · y426', (tester) async {
      // 묶음 298 = pen 구멍 306 − 사방 4 × 2.
      await pump(tester, size: const Size(360, 780), freeHeight: 298, heartBar: 88);
      await toLastStep(tester);

      expect(inBubble('6 / 6'), findsOneWidget);
      expect(overlay(tester).hole, const Rect.fromLTWH(12, 68, 336, 306));
      expect(overlay(tester).radius, 16);
      final bubble = tester.getRect(find.byType(CoachBubble));
      expect((bubble.left, bubble.top, bubble.width), (24.0, 426.0, 312.0));
      final line = tester.getRect(find.byType(CoachLine));
      expect((line.top, line.bottom), (374.0, 426.0));
      expect(tester.widget<CoachLine>(find.byType(CoachLine)).dotAtTop, isTrue);
      expect(bubbleWhole(tester), isTrue);
    });

    testWidgets('6단계 대상이 화면보다 길면(360×600 · 묶음 900) 위쪽을 앱바 아래 12 에 두고, 구멍 아래를 하단 바 위 말풍선 · 선 자리만큼 자른다', (tester) async {
      await pump(tester, size: const Size(360, 600), freeHeight: 900, heartBar: 88);
      await toLastStep(tester);

      final hole = overlay(tester).hole!;
      final bar = tester.getRect(find.byKey(_bar));
      expect(hole.top, 56 + 12);
      expect(tester.getTopLeft(find.byKey(_free)).dy, hole.top + 4);
      final bubble = tester.getRect(find.byType(CoachBubble));
      expect(bubbleWhole(tester), isTrue);
      // 선은 줄이지 않는다 — 구멍을 잘라 자리를 냈다.
      expect(bubble.top, hole.bottom + 52);
      expect(bubble.bottom, closeTo(bar.top - 16, 0.01));
    });

    testWidgets('말풍선 자리가 선 길이만큼 모자라면 선부터 줄인다 — 말풍선은 잘리지 않고 화면 아래 여백 16 을 지킨다', (tester) async {
      await pump(tester);
      await start(tester);
      final natural = tester.getSize(find.byType(CoachBubble)).height;

      // 히어로 위 16 · 구멍 띄움 2 · 화면 아래 여백 16 — 구멍 아래 자리가 말풍선 + 30 이 되게 히어로를 키운다.
      pages.heroHeight.value = 740 - 16 - (16 + 2) - natural - 30;
      await tester.pumpAndSettle();

      final hole = overlay(tester).hole!;
      final bubble = tester.getRect(find.byType(CoachBubble));
      expect(bubble.height, natural);
      expect(bubbleWhole(tester), isTrue);
      expect(bubble.top - hole.bottom, closeTo(30, 0.01));
      expect(tester.getSize(find.byType(CoachLine)).height, closeTo(30, 0.01));
      expect(bubble.bottom, closeTo(740 - 16, 0.01));
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('작은 화면(360×600) · 글자 $scale · 긴 6단계 묶음(900)으로 다 돌아도 구멍 · 말풍선이 화면 안이고, 6단계 구멍은 앱바와 하단 바 사이', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pump(tester, size: const Size(360, 600), freeHeight: 900, heartBar: 88);
        await start(tester);

        for (var step = 1; step <= 6; step++) {
          expect(tester.takeException(), isNull, reason: '$step단계');
          // 보이는 말풍선 틀(말풍선을 품은 스크롤 칸) — 5단계처럼 화면보다 길면 틀 안이 스크롤된다.
          final bubble = tester.getRect(
            find.ancestor(of: find.byType(CoachBubble).hitTestable(), matching: find.byType(Scrollable)).first,
          );
          expect(bubble.top, greaterThanOrEqualTo(0), reason: '$step단계');
          expect(bubble.bottom, lessThanOrEqualTo(600), reason: '$step단계');
          final hole = overlay(tester).hole;
          if (hole != null) {
            expect(hole.top, greaterThanOrEqualTo(0), reason: '$step단계');
            expect(hole.bottom, lessThanOrEqualTo(600), reason: '$step단계');
          }
          if (step == 6) break;
          // 말풍선이 틀보다 길면(5단계 · 글자 2.0) "다음" 이 틀 밖이라 사람처럼 말풍선 안을 밀어 보이게 한 뒤 누른다.
          await tester.ensureVisible(find.descendant(of: find.byType(CoachBubble), matching: find.byType(AppButton)));
          await next(tester);
        }
        expect(inBubble('6 / 6'), findsOneWidget);
        final hole = overlay(tester).hole!;
        expect(hole.top, greaterThanOrEqualTo(56));
        expect(hole.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(_bar)).top));
      });
    }

    ScrollPosition storeList(WidgetTester tester) =>
        tester.state<ScrollableState>(find.ancestor(of: find.byKey(_free), matching: find.byType(Scrollable)).first).position;

    testWidgets('6단계를 뒤로가기로 끝내면 빈자리를 바로 빼지 않고 목록 끝까지 부드럽게 내린 뒤 뺀다 — 한 프레임에 튀지 않는다', (tester) async {
      await pump(tester);
      await toLastStep(tester);
      final list = storeList(tester);
      final start = list.pixels;
      final end = list.maxScrollExtent - 740; // 빈자리(화면 높이)를 뺀 목록 끝
      expect(start, greaterThan(end));

      await tester.binding.handlePopRoute();
      final seen = [start];
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(list.pixels);
      }
      await tester.pumpAndSettle();

      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], lessThanOrEqualTo(seen[i - 1] + 0.01), reason: '$i 프레임 — 한 방향으로만');
        expect(seen[i - 1] - seen[i], lessThan((start - end) / 2), reason: '$i 프레임 — 급점프 없음');
      }
      expect(list.pixels, closeTo(end, 0.01));
      expect(list.pixels, closeTo(list.maxScrollExtent, 0.01));
      expect(tester.getSize(find.byType(TourScrollRoom, skipOffstage: false)).height, 0);
      expect(find.byType(CoachOverlay), findsNothing);
    });

    testWidgets('동작 줄이기면 6단계를 끝낼 때 빈자리를 바로 빼고 목록은 바로 끝에 있다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pump(tester);
      await toLastStep(tester);
      final list = storeList(tester);
      final end = list.maxScrollExtent - 740;

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();

      expect(tester.getSize(find.byType(TourScrollRoom, skipOffstage: false)).height, 0);
      expect(list.pixels, closeTo(end, 0.01));
    });

    testWidgets('목록 끝 빈자리(TourScrollRoom)는 6단계 동안만 화면 높이만큼 늘고 투어가 끝나면 0 — 호스트가 없으면 늘 0', (tester) async {
      await pump(tester);
      Size room() => tester.getSize(find.byType(TourScrollRoom, skipOffstage: false));
      await toLastStep(tester);
      expect(room().height, 740);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(room().height, 0);

      await tester.pumpWidget(
        const MaterialApp(home: Column(children: [TourScrollRoom(id: TourTargetId.heartStoreFree)])),
      );
      expect(tester.getSize(find.byType(TourScrollRoom)).height, 0);
    });
  });

  group('모션', () {
    testWidgets('처음엔 덮개가 투명에서 나타나고, 다음 단계로 갈 때 구멍이 앞 대상에서 이어 움직인다', (tester) async {
      await pump(tester);
      container.read(appTourViewModelProvider.notifier).replay();
      await tester.pump();
      await tester.pump();
      expect(overlayOpacity(tester), lessThan(1));
      await tester.pumpAndSettle();
      expect(overlayOpacity(tester), 1);

      final from = overlay(tester).hole!;
      await tester.tap(find.descendant(of: find.byType(CoachBubble), matching: find.byType(AppButton)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final moving = overlay(tester).hole!;
      await tester.pumpAndSettle();
      final arrived = overlay(tester).hole!;
      expect(arrived, rectOf(tester, _nudge).inflate(2));
      // 앞 대상에서 순간이동하지 않고 그 사이를 지난다.
      expect(moving, isNot(from));
      expect(moving, isNot(arrived));
    });

    testWidgets('기기 "동작 줄이기"면 덮개 · 구멍 · 말풍선이 첫 프레임부터 최종 상태다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pump(tester);

      container.read(appTourViewModelProvider.notifier).replay();
      await tester.pump();
      await tester.pump();

      expect(overlayOpacity(tester), 1);
      expect(overlay(tester).hole, rectOf(tester, _hero).inflate(2));
      final bubbleOpacity = tester.widget<Opacity>(
        find.ancestor(of: find.byType(CoachBubble), matching: find.byType(Opacity)).first,
      );
      expect(bubbleOpacity.opacity, 1);
    });
  });

  testWidgets('스크린리더 — 말풍선의 단계 · 제목 · 설명만 읽히고 덮개 밑 화면은 읽히지 않는다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    await start(tester);

    // 실제 의미 트리에서 찾는다 — 렌더 객체에 남은 지난 의미 정보가 아니라.
    expect(find.semantics.byLabel('6단계 중 1단계'), findsOne);
    expect(find.semantics.byLabel('여기가 캠퍼스메이트의 시작이에요'), findsOne);
    expect(find.semantics.byLabel('밑 버튼'), findsNothing);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('밑 버튼'), findsOne);
    handle.dispose();
  });
}
