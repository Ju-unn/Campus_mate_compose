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
