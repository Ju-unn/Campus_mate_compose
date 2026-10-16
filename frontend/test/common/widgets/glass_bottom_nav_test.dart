import 'dart:ui' show ImageFilter;

import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/core/haptics/haptics_gateway.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics/fake_haptics_gateway.dart';

/// pen `MX4jk` 견본(`hseoX`)과 같은 360 폭 · 바닥 safe area 20.
const _screen = Size(360, 780);
const _safeBottom = 20.0;

const _routes = {
  AppTab.main: AppRoutes.home,
  AppTab.today: AppRoutes.today,
  AppTab.community: AppRoutes.community,
  AppTab.chat: AppRoutes.conversations,
  AppTab.me: AppRoutes.myProfile,
};

const _labels = ['메인', '오늘', '커뮤니티', '대화', '나'];

/// 탭 화면 다섯 개. 전환 움직임 없이 갈아 끼워 방울 위치를 화면 변환 없이 잰다.
Future<FakeHapticsGateway> _pump(
  WidgetTester tester, {
  AppTab start = AppTab.main,
  int badge = 0,
  Size screen = _screen,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: _safeBottom);
  addTearDown(tester.view.reset);
  final haptics = FakeHapticsGateway();
  final router = GoRouter(
    initialLocation: _routes[start]!,
    routes: [
      for (final MapEntry(key: tab, value: path) in _routes.entries)
        GoRoute(
          path: path,
          // 앱의 GoRoute 처럼 경로마다 다른 pageKey — 키가 없으면 Navigator 가 앞 화면을 고쳐 써 내비 상태가 남는다.
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: Scaffold(
              extendBody: true,
              body: Text('${tab.name} 화면'),
              bottomNavigationBar: GlassBottomNav(current: tab),
            ),
          ),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hapticsGatewayProvider.overrideWithValue(haptics),
        chatBadgeCountProvider.overrideWithValue(badge),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return haptics;
}

Finder _nav([AppTab? current]) => current == null
    ? find.byType(GlassBottomNav)
    : find.byWidgetPredicate((w) => w is GlassBottomNav && w.current == current);

/// 알약 = 블러 층(알약 모양으로 잘린 BackdropFilter)의 자리.
Rect _pill(WidgetTester tester, [AppTab? current]) =>
    tester.getRect(find.descendant(of: _nav(current), matching: find.byType(BackdropFilter)));

/// 선택 방울 — pen `ANnU7` 등 채움 #FFFFFF99 인 상자.
Finder _bubble([AppTab? current]) => find.descendant(
  of: _nav(current),
  matching: find.byWidgetPredicate(
    (w) => w is DecoratedBox && (w.decoration as BoxDecoration).color == const Color(0x99FFFFFF),
  ),
);

Rect _bubbleInPill(WidgetTester tester, [AppTab? current]) =>
    tester.getRect(_bubble(current)).shift(-_pill(tester, current).topLeft);

Finder _label(String text) => find.descendant(of: find.byType(GlassBottomNav), matching: find.text(text));

const _primary = Color(0xFFFF385C);
const _body = Color(0xFF3F3F3F);

Color? _iconColor(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.descendant(of: _nav(), matching: find.byIcon(icon))).color;

/// 알약 기준 x · 알약 세로 가운데의 화면 좌표.
Offset _onPill(WidgetTester tester, double x) {
  final pill = _pill(tester);
  return pill.topLeft + Offset(x, pill.height / 2);
}

/// 알약 x 에서 누르고 오른쪽으로 20 밀어(터치 기준 18 을 넘겨) 끌기를 시작한 뒤, 손가락 밑으로 건너오기가 끝날 때까지 기다린다.
Future<TestGesture> _startDrag(WidgetTester tester, double x) async {
  final gesture = await tester.startGesture(_onPill(tester, x));
  await gesture.moveBy(const Offset(20, 0));
  // 첫 프레임이 움직임의 시작 시각이다 — 빈 pump 없이 200ms 를 한 번에 넘기면 경과 0 으로 남는다.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return gesture;
}

/// 손가락을 알약 x 로 옮기고 한 프레임 그린다.
Future<void> _dragTo(WidgetTester tester, TestGesture gesture, double x) async {
  await gesture.moveTo(_onPill(tester, x));
  await tester.pump();
}

void main() {
  group('알약 자리와 모양(pen `xtj0K`)', () {
    testWidgets('328×66 알약이 좌우 16 · 바닥 safe area 20 + 띄움 12 위에 뜬다(y = 780 − 98 = 682, `hseoX` 의 `kk3Oc`)', (
      tester,
    ) async {
      await _pump(tester);

      expect(_pill(tester), const Rect.fromLTWH(16, 682, 328, 66));
      // 내비 자리 전체 = 알약 66 + 띄움 12 + safe area 20 — Scaffold 가 이 높이를 본문 아래 여백으로 넘긴다.
      expect(tester.getRect(_nav()), const Rect.fromLTWH(0, 682, 360, 98));
    });

    testWidgets('채움 #FFFFFFC7(78%) · 안쪽 1px #FFFFFF99 · 배경 블러 20', (tester) async {
      await _pump(tester);

      final blur = tester.widget<BackdropFilter>(find.descendant(of: _nav(), matching: find.byType(BackdropFilter)));
      expect(blur.filter, ImageFilter.blur(sigmaX: 20, sigmaY: 20));
      final fill = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(BackdropFilter), matching: find.byType(DecoratedBox)),
      );
      final decoration = fill.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xC7FFFFFF));
      // 안쪽 선은 자식을 밀지 않는다 — DecoratedBox 의 테두리, 안쪽 정렬(기본).
      expect(decoration.border, Border.all(color: const Color(0x99FFFFFF)));
      expect(_pill(tester).size, tester.getSize(find.byWidget(fill)));
    });

    testWidgets('그림자 (0,8) blur 24 #1A16191F 는 알약 바깥에만 그린다 — 반투명 채움 사이로 비치지 않게', (tester) async {
      await _pump(tester);

      final pillShadow = find
          .descendant(of: _nav(), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null))
          .first;
      expect(tester.getSize(pillShadow), const Size(328, 66));
      expect(
        tester.renderObject(pillShadow),
        paints
          ..save()
          ..clipPath()
          ..rrect(rrect: RRect.fromLTRBR(0, 8, 328, 74, const Radius.circular(33)), color: const Color(0x1F1A1619))
          ..restore(),
      );
    });

    testWidgets('알약은 RepaintBoundary 안에 있다 — 본문이 스크롤돼도 내비 그림을 다시 그리지 않는다', (tester) async {
      await _pump(tester);

      expect(find.descendant(of: _nav(), matching: find.byType(RepaintBoundary)), findsWidgets);
      final boundary = tester.renderObject(find.descendant(of: _nav(), matching: find.byType(RepaintBoundary)).first);
      expect(boundary.isRepaintBoundary, isTrue);
      expect(tester.getRect(find.descendant(of: _nav(), matching: find.byType(RepaintBoundary)).first), tester.getRect(_nav()));
    });
  });

  group('탭 칸(pen `PLq2b` 등 64×58)', () {
    testWidgets('다섯 칸 순서 · 아이콘 24 · 칸은 64×58 · 아이콘 y12 · 라벨 y38 높이 16(알약 기준)', (tester) async {
      await _pump(tester);

      final pill = _pill(tester);
      const icons = [AppIcons.house, AppIcons.heart, AppIcons.users, AppIcons.messageCircle, AppIcons.userRound];
      for (var i = 0; i < 5; i++) {
        final icon = find.descendant(of: _nav(), matching: find.byIcon(icons[i]));
        expect(tester.getRect(icon).shift(-pill.topLeft), Rect.fromLTWH(4 + 64.0 * i + 20, 12, 24, 24), reason: _labels[i]);
        final label = tester.getRect(_label(_labels[i])).shift(-pill.topLeft);
        expect((label.top, label.height), (38, 16), reason: _labels[i]);
        final cell = find.ancestor(of: _label(_labels[i]), matching: find.byType(InkWell));
        expect(tester.getRect(cell).shift(-pill.topLeft), Rect.fromLTWH(4 + 64.0 * i, 4, 64, 58), reason: _labels[i]);
      }
    });

    testWidgets('고른 탭은 아이콘 #FF385C · 라벨 #C4224B, 나머지는 body #3F3F3F. 라벨 11/600(lineHeight · letterSpacing 속성 없음, 렌더 16)', (
      tester,
    ) async {
      await _pump(tester, start: AppTab.community);

      const icons = [AppIcons.house, AppIcons.heart, AppIcons.users, AppIcons.messageCircle, AppIcons.userRound];
      for (var i = 0; i < 5; i++) {
        final selected = i == 2;
        final icon = tester.widget<Icon>(find.descendant(of: _nav(), matching: find.byIcon(icons[i])));
        expect(icon.color, selected ? const Color(0xFFFF385C) : const Color(0xFF3F3F3F), reason: _labels[i]);
        final style = tester.widget<Text>(_label(_labels[i])).style!;
        expect(style.color, selected ? const Color(0xFFC4224B) : const Color(0xFF3F3F3F), reason: _labels[i]);
        expect((style.fontSize, style.fontWeight, style.letterSpacing), (11, FontWeight.w600, 0), reason: _labels[i]);
      }
    });

    testWidgets('눌림 효과는 칸 크기 Material 에 그린다(COMMON §4-2) — 화면 전체 Material 이 아니다', (tester) async {
      await _pump(tester);

      for (final label in _labels) {
        final ink = find.ancestor(of: _label(label), matching: find.byType(InkWell));
        final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
        expect(tester.getSize(material), tester.getSize(ink), reason: label);
      }
    });
  });

  group('선택 방울 C(pen `ANnU7` · `e5De2` · `bTYXh` · `xWvRT` · `g6Wcb`)', () {
    // 칸 x(4 + 64i) − 6, 폭 76. 메인 · 나는 알약 밖으로 2px 나가던 것을 안으로 당겼다(사용자 결정 10-13: 메인 x0 · 나 x252).
    const expectedX = {AppTab.main: 0.0, AppTab.today: 62.0, AppTab.community: 126.0, AppTab.chat: 190.0, AppTab.me: 252.0};
    for (final MapEntry(key: tab, value: x) in expectedX.entries) {
      testWidgets('${tab.name} 선택 — 방울은 알약 기준 x$x y6 76×54', (tester) async {
        await _pump(tester, start: tab);

        expect(_bubble(), findsOneWidget);
        expect(_bubbleInPill(tester), Rect.fromLTWH(x, 6, 76, 54));
      });
    }

    testWidgets('채움 #FFFFFF99 · 위쪽만 1px #FFFFFFE6 · 모서리 27 · 그림자 (0,5) blur 12 #1A161933 은 방울 바깥에만', (tester) async {
      await _pump(tester);

      final decoration = tester.widget<DecoratedBox>(_bubble()).decoration as BoxDecoration;
      expect(decoration.border, const Border(top: BorderSide(color: Color(0xE6FFFFFF))));
      expect(decoration.borderRadius, BorderRadius.circular(27));
      final shadow = find.ancestor(of: _bubble(), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null)).first;
      expect(tester.getSize(shadow), const Size(76, 54));
      expect(
        tester.renderObject(shadow),
        paints
          ..save()
          ..clipPath()
          ..rrect(rrect: RRect.fromLTRBR(0, 5, 76, 59, const Radius.circular(27)), color: const Color(0x331A1619))
          ..restore(),
      );
    });

    testWidgets('알약 폭이 바뀌어도 칸은 5등분, 방울은 칸보다 12 넓고 알약 안에 머문다(412 폭)', (tester) async {
      await _pump(tester, start: AppTab.me, screen: const Size(412, 780));

      final pill = _pill(tester);
      expect(pill.width, 412 - 32);
      const cell = (412 - 32 - 8) / 5;
      final bubble = _bubbleInPill(tester);
      expect(bubble.width, closeTo(cell + 12, 0.001));
      expect(bubble.right, closeTo(pill.width, 0.001));
    });
  });

  group('탭 전환 · 진동', () {
    testWidgets('다른 탭을 누르면 그 탭 화면으로 가고 selectionClick 진동이 한 번 울린다', (tester) async {
      final haptics = await _pump(tester);

      await tester.tap(_label('오늘'));
      await tester.pumpAndSettle();

      expect(find.text('today 화면'), findsOneWidget);
      expect(haptics.selectionClicks, 1);
    });

    testWidgets('같은 탭을 다시 누르면 진동하지 않고 방울도 그대로다', (tester) async {
      final haptics = await _pump(tester, start: AppTab.chat);

      await tester.tap(_label('대화'));
      await tester.pumpAndSettle();

      expect(find.text('chat 화면'), findsOneWidget);
      expect(haptics.selectionClicks, 0);
      expect(_bubbleInPill(tester).left, 190);
    });

    testWidgets('방울은 앞 탭 자리에서 새 탭으로 x 만 미끄러진다 — 120ms ease-out(pen 80~200ms)', (tester) async {
      await _pump(tester);

      await tester.tap(_label('커뮤니티'));
      await tester.pump();
      await tester.pump();
      // 새 탭 화면의 첫 그림: 방울은 아직 메인 자리.
      expect(_bubbleInPill(tester, AppTab.community), const Rect.fromLTWH(0, 6, 76, 54));
      await tester.pump(const Duration(milliseconds: 60));
      final middle = _bubbleInPill(tester, AppTab.community);
      expect(middle.left, inExclusiveRange(0, 126));
      expect((middle.top, middle.size), (6, const Size(76, 54)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_bubbleInPill(tester, AppTab.community).left, 126);
    });

    testWidgets('모션 줄이기가 켜져 있으면 방울이 움직이지 않고 첫 그림부터 새 탭 자리 · 진동은 그대로', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final haptics = await _pump(tester);

      await tester.tap(_label('나'));
      await tester.pump();
      await tester.pump();

      expect(_bubbleInPill(tester, AppTab.me).left, 252);
      expect(haptics.selectionClicks, 1);
    });

    testWidgets('탭이 아닌 길로 들어온 탭(메인 히어로 → 오늘 등)은 방울이 처음부터 제자리다', (tester) async {
      await _pump(tester);

      GoRouter.of(tester.element(find.text('main 화면'))).go(AppRoutes.today);
      await tester.pump();
      await tester.pump();

      expect(_bubbleInPill(tester, AppTab.today).left, 62);
    });
  });

  // 알약 위에서 끌면 방울이 손가락을 따르고, 놓으면 손가락 밑 탭이 열린다(2026-10-16 사용자 요청 "드래그해서 움직이고 멈추면
  // 그 탭 열리는거" · "1번 A로 진행해줘", 대장 결정 Q1=B · Q2=A · Q3=A · Q4=A). 360 폭: 칸 64, 칸 경계 x 68 · 132 · 196 · 260,
  // 방울 가운데 = 손가락 x 라 방울 x = 손가락 − 38(0 ~ 252 로 자른다).
  group('끌어서 옮기기', () {
    testWidgets('끌다 놓으면 손가락 밑 탭이 한 번 열리고, 새 화면 방울은 놓은 자리 x172 에서 120ms 에 x190 으로 간다 · 진동 1회', (tester) async {
      final haptics = await _pump(tester);
      final gesture = await _startDrag(tester, 36);
      await _dragTo(tester, gesture, 210);

      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(find.text('chat 화면'), findsOneWidget);
      expect(_bubbleInPill(tester, AppTab.chat).left, closeTo(172, 0.001));
      await tester.pump(const Duration(milliseconds: 120));
      expect(_bubbleInPill(tester, AppTab.chat).left, closeTo(190, 0.001));
      expect(haptics.selectionClicks, 1);
    });

    testWidgets('끄는 동안에는 화면이 그대로고 방울 가운데가 손가락을 1:1 로 따른다(크기 76×54 · y6 그대로)', (tester) async {
      await _pump(tester);
      final gesture = await _startDrag(tester, 36);

      for (final x in [90.0, 150.0, 240.0]) {
        await _dragTo(tester, gesture, x);
        final bubble = _bubbleInPill(tester);
        expect(bubble.left, closeTo(x - 38, 0.001), reason: '손가락 $x');
        expect((bubble.top, bubble.size), (6, const Size(76, 54)), reason: '손가락 $x');
      }
      expect(find.text('main 화면'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('방울 밖(나 칸)에서 끌기 시작하면 방울이 지금 자리에서 손가락 밑으로 120ms 에 건너오고 그 탭이 강조된다', (tester) async {
      await _pump(tester);
      final gesture = await tester.startGesture(_onPill(tester, 292));
      await gesture.moveBy(const Offset(-20, 0)); // x 272 에서 끌기가 시작된다.

      await tester.pump();
      expect(_bubbleInPill(tester).left, 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_bubbleInPill(tester).left, inExclusiveRange(0, 234));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_bubbleInPill(tester).left, closeTo(234, 0.001));
      expect(_iconColor(tester, AppIcons.userRound), _primary);
      expect(_iconColor(tester, AppIcons.house), _body);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('끄는 동안 손가락 밑 탭만 색이 바뀌고, 화면 읽기의 선택은 지금 탭 그대로다', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      final gesture = await _startDrag(tester, 36);

      await _dragTo(tester, gesture, 164);

      expect(_iconColor(tester, AppIcons.users), _primary);
      expect(tester.widget<Text>(_label('커뮤니티')).style!.color, const Color(0xFFC4224B));
      expect(_iconColor(tester, AppIcons.house), _body);
      expect(tester.widget<Text>(_label('메인')).style!.color, _body);
      expect(tester.getSemantics(_label('메인')), isSemantics(hasSelectedState: true, isSelected: true));
      expect(tester.getSemantics(_label('커뮤니티')), isSemantics(hasSelectedState: true, isSelected: false));

      await gesture.up();
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('경계(68)를 4 넘게 지나야 강조가 바뀐다 — 떨어도 깜빡이지 않고, 끄는 중에는 진동하지 않는다', (tester) async {
      final haptics = await _pump(tester);
      final gesture = await _startDrag(tester, 36);

      Future<Color?> houseAt(double x) async {
        await _dragTo(tester, gesture, x);
        return _iconColor(tester, AppIcons.house);
      }

      expect(await houseAt(71), _primary, reason: '68 + 3 — 아직 메인');
      expect(await houseAt(73), _body, reason: '68 + 5 — 오늘로');
      expect(await houseAt(65), _body, reason: '68 − 3 — 아직 오늘');
      expect(await houseAt(63), _primary, reason: '68 − 5 — 메인으로');
      expect(haptics.selectionClicks, 0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('main 화면'), findsOneWidget);
      expect(haptics.selectionClicks, 0);
    });

    // pen 견본: 손가락 136(경계 132 + 4) · 방울 x98 → 커뮤니티. 정확히 4 지난 자리에서 바뀌고, 3 은 그대로다(돌아올 때도 같다).
    testWidgets('경계를 정확히 4 지나면 강조가 바뀌고 3 이면 그대로다 — 손가락 136 · 방울 x98 은 커뮤니티(pen 견본)', (tester) async {
      await _pump(tester);
      final gesture = await _startDrag(tester, 36);
      const icons = [AppIcons.house, AppIcons.heart, AppIcons.users, AppIcons.messageCircle, AppIcons.userRound];

      Future<String> highlightAt(double x) async {
        await _dragTo(tester, gesture, x);
        return _labels[icons.indexWhere((icon) => _iconColor(tester, icon) == _primary)];
      }

      expect(await highlightAt(72), '오늘', reason: '68 + 4');
      expect(await highlightAt(65), '오늘', reason: '68 − 3');
      expect(await highlightAt(64), '메인', reason: '68 − 4');
      expect(await highlightAt(72), '오늘', reason: '68 + 4');
      expect(await highlightAt(135), '오늘', reason: '132 + 3');
      expect(await highlightAt(136), '커뮤니티', reason: '132 + 4');
      expect(_bubbleInPill(tester).left, closeTo(98, 0.001));
      expect(await highlightAt(129), '커뮤니티', reason: '132 − 3');
      expect(await highlightAt(128), '오늘', reason: '132 − 4');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('today 화면'), findsOneWidget);
    });

    testWidgets('처음 탭으로 돌아와 놓으면 화면 이동 · 진동이 없고 방울이 놓은 자리에서 120ms 에 제자리로 간다', (tester) async {
      final haptics = await _pump(tester);
      final gesture = await _startDrag(tester, 36);
      await _dragTo(tester, gesture, 150);
      await _dragTo(tester, gesture, 50);

      await gesture.up();
      await tester.pump();

      expect(find.text('main 화면'), findsOneWidget);
      expect(_bubbleInPill(tester).left, closeTo(12, 0.001));
      await tester.pump(const Duration(milliseconds: 120));
      expect(_bubbleInPill(tester).left, closeTo(0, 0.001));
      expect(haptics.selectionClicks, 0);
    });

    // Flutter 는 끌기가 시작된 뒤 시스템이 터치를 빼앗아도(전화 · 알림창 · 홈 제스처) onEnd 를 부른다 — 탭이 바뀌면 안 된다.
    testWidgets('끄는 중 시스템이 터치를 취소하면 이동 · 진동 없이 방울과 강조가 지금 탭으로 돌아간다', (tester) async {
      final haptics = await _pump(tester);
      final gesture = await _startDrag(tester, 36);
      await _dragTo(tester, gesture, 228);

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(find.text('main 화면'), findsOneWidget);
      expect(find.text('chat 화면'), findsNothing);
      expect(_bubbleInPill(tester).left, closeTo(0, 0.001));
      expect(_iconColor(tester, AppIcons.house), _primary);
      expect(haptics.selectionClicks, 0);
    });

    testWidgets('손가락이 알약 밖으로 나가도 따라간다 — 좌우 끝은 x0 · x252 에서 멈추고, 위로 벗어나도 x 를 따라 놓은 탭이 열린다', (tester) async {
      await _pump(tester);
      final gesture = await _startDrag(tester, 36);

      await _dragTo(tester, gesture, -60);
      expect(_bubbleInPill(tester).left, 0);
      await _dragTo(tester, gesture, 420);
      expect(_bubbleInPill(tester).left, 252);
      await gesture.moveTo(_onPill(tester, 164) - const Offset(0, 200));
      await tester.pump();
      expect(_bubbleInPill(tester).left, closeTo(126, 0.001));

      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(find.text('community 화면'), findsOneWidget);
    });

    testWidgets('끄는 중 두 번째 손가락은 탭을 열지 않고, 방울은 그 손가락 쪽으로 튀지 않고 움직인 만큼만 간다', (tester) async {
      final haptics = await _pump(tester);
      final first = await _startDrag(tester, 36);
      await _dragTo(tester, first, 100);

      final second = await tester.startGesture(_onPill(tester, 292));
      await second.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(_bubbleInPill(tester).left, closeTo(72, 0.001), reason: '손가락 100 + 10');
      await second.up();
      await tester.pump();
      expect(find.text('main 화면'), findsOneWidget);

      await first.up();
      await tester.pump();
      await tester.pump();
      expect(find.text('today 화면'), findsOneWidget);
      expect(haptics.selectionClicks, 1);
    });

    testWidgets('놓은 직후 방울이 움직이는 중에 다시 끌어도 지금 자리에서 이어진다', (tester) async {
      await _pump(tester);
      final gesture = await _startDrag(tester, 36);
      await _dragTo(tester, gesture, 210);
      await gesture.up();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final before = _bubbleInPill(tester, AppTab.chat).left;
      expect(before, inExclusiveRange(172, 190));

      final again = await tester.startGesture(_onPill(tester, 228));
      await again.moveBy(const Offset(-20, 0)); // x 208 에서 다시 끌기.
      await tester.pump();
      expect(_bubbleInPill(tester, AppTab.chat).left, closeTo(before, 0.001));
      await tester.pump(const Duration(milliseconds: 120));
      expect(_bubbleInPill(tester, AppTab.chat).left, closeTo(170, 0.001));

      await again.up();
      await tester.pumpAndSettle();
    });

    testWidgets('모션 줄이기면 건너오기 · 제자리 찾기는 바로, 끌면 그대로 따라가고 진동 1회 · pumpAndSettle 이 끝난다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final haptics = await _pump(tester);
      final gesture = await tester.startGesture(_onPill(tester, 292));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      expect(_bubbleInPill(tester).left, closeTo(234, 0.001), reason: '건너오기 없이 바로 손가락 밑');

      await _dragTo(tester, gesture, 210);
      expect(_bubbleInPill(tester).left, closeTo(172, 0.001), reason: '끌면 그대로 따라간다');
      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(_bubbleInPill(tester, AppTab.chat).left, closeTo(190, 0.001));
      expect(haptics.selectionClicks, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('화면 읽기 트리에 가로 스크롤 동작이 생기지 않는다 — 낭독기 사용자는 탭 방식 그대로', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      expect(find.semantics.byAction(SemanticsAction.scrollLeft), findsNothing);
      expect(find.semantics.byAction(SemanticsAction.scrollRight), findsNothing);
      semantics.dispose();
    });

    for (final (screen, scale) in [(const Size(412, 780), 1.0), (_screen, 2.0)]) {
      testWidgets('폭 ${screen.width.toInt()} · 글자 배율 $scale — 대화 칸 가운데에서 놓으면 대화가 열리고 넘침이 없다', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, screen: screen);
        final cell = (screen.width - 32 - 8) / 5;
        final chatCenter = 4 + cell * 3.5;
        final gesture = await _startDrag(tester, 4 + cell / 2);

        await _dragTo(tester, gesture, chatCenter);
        expect(_bubbleInPill(tester).left, closeTo(chatCenter - (cell + 12) / 2, 0.001));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('chat 화면'), findsOneWidget);
        expect(_bubbleInPill(tester, AppTab.chat).left, closeTo(4 + 3 * cell - 6, 0.001));
      });
    }
  });

  group('대화 탭 배지(pen `A6Xn1I`, DESIGN §8.8)', () {
    testWidgets('수가 있으면 "대화" 오른쪽 4 에 높이 16 · 최소 폭 16 배지(폭은 글꼴 따라 — 테스트 글꼴 숫자는 Pretendard 보다 넓다)', (tester) async {
      await _pump(tester, badge: 3);

      final badge = find.descendant(of: _nav(), matching: find.text('3'));
      expect(badge, findsOneWidget);
      final box = find.ancestor(of: badge, matching: find.byType(Container)).first;
      expect(tester.getSize(box).height, 16);
      expect(tester.widget<Container>(box).constraints, const BoxConstraints(minWidth: 16, minHeight: 16));
      expect((tester.widget<Container>(box).decoration! as BoxDecoration).color, const Color(0xFFFF385C));
      expect(tester.getTopLeft(box).dx - tester.getTopRight(_label('대화')).dx, 4);
    });

    testWidgets('세 자리면 99+ 로 줄인다', (tester) async {
      await _pump(tester, badge: 105);

      expect(find.descendant(of: _nav(), matching: find.text('99+')), findsOneWidget);
    });

    testWidgets('0 이면 배지가 없다', (tester) async {
      await _pump(tester);

      expect(find.descendant(of: _nav(), matching: find.text('0')), findsNothing);
    });
  });

  group('접근성', () {
    testWidgets('탭마다 버튼 · 고른 탭만 selected · 라벨은 탭 이름(배지 수는 말로 붙는다)', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, start: AppTab.today, badge: 2);

      for (final label in _labels) {
        expect(
          tester.getSemantics(_label(label)),
          isSemantics(
            label: label == '대화' ? '대화\n안 읽음 2개' : label,
            isButton: true,
            hasSelectedState: true,
            isSelected: label == '오늘',
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
          reason: label,
        );
      }
      semantics.dispose();
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale — 넘침 오류가 없고 아이콘 · 라벨이 알약 안에서 세로로 잘리지 않는다', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, badge: 4);

        expect(tester.takeException(), isNull);
        final pill = _pill(tester);
        expect(pill.height, greaterThanOrEqualTo(66));
        for (final element in find.descendant(of: _nav(), matching: find.byType(RichText)).evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          final box = tester.getRect(find.byElementPredicate((e) => e == element));
          final text = paragraph.text.toPlainText();
          expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5), reason: text);
          expect(box.top >= pill.top && box.bottom <= pill.bottom, isTrue, reason: '$text $box / $pill');
        }
      });
    }
  });
}
