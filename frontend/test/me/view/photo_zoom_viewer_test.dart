import 'dart:convert';

import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/view/photo_zoom_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 3×4 투명 PNG — 세로 3:4 사진이라 폭 360 에 가득 채우면 360×480(pen 견본 크기)이 된다.
final _portraitPng = MemoryImage(
  base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAMAAAAECAYAAABLLYUHAAAADElEQVR4nGNgIB0AAAA0AAF2Xq7DAAAAAElFTkSuQmCC'),
);

const _guide = '두 손가락으로 크게 볼 수 있어요';

/// 15-7 사진 확대 뷰어(pen `ZExxs` "내 사진 수정 · 사진 확대 (초안)", 대장 값표 2026-10-16).
void main() {
  /// pen 화면 360×780, 상태 표시줄 44(닫기 버튼 y44 가 상태 표시줄 바로 아래다).
  void usePenFrame(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44);
    addTearDown(tester.view.reset);
  }

  /// 앞 화면에 "열기" 버튼 하나 — 누르면 뷰어가 [index] 번째 사진으로 열린다.
  Future<void> pumpHost(WidgetTester tester, {int index = 1, bool disableAnimations = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPhotoZoomViewer(context, image: _portraitPng, index: index),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    // 그림 풀기는 엔진이 실제로 해야 끝난다 — 미리 풀어 두면 뷰어가 바로 진짜 크기로 그린다.
    await tester.runAsync(() => precacheImage(_portraitPng, tester.element(find.text('열기'))));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  group('pen 값(ZExxs, 배율 1.0, 360×780 · 상태 표시줄 44)', () {
    testWidgets('바탕 `ITtLC` — ink 알파 .9(#222222E6) 로 화면 전체를 덮는다', (tester) async {
      usePenFrame(tester);
      await pumpHost(tester);
      await open(tester);

      final barrier = tester.widget<ModalBarrier>(find.byType(ModalBarrier).last);
      expect(barrier.color, const Color(0xE6222222));
      expect(tester.getRect(find.byType(ModalBarrier).last), const Rect.fromLTWH(0, 0, 360, 780));
    });

    testWidgets('사진 `FgziF` — 화면 폭 가득 contain, 세로 가운데(3:4 면 360×480 · y150)', (tester) async {
      usePenFrame(tester);
      await pumpHost(tester);
      await open(tester);

      final photo = find.descendant(of: find.byType(PhotoZoomViewer), matching: find.byType(Image));
      expect(tester.widget<Image>(photo).image, _portraitPng);
      expect(tester.widget<Image>(photo).fit, BoxFit.contain);
      expect(tester.getRect(photo), const Rect.fromLTWH(0, 150, 360, 480));
    });

    testWidgets('닫기 — 오른쪽 위 48×48 누름 칸(x304 · y44, 상태 표시줄 아래), lucide x 24 흰색, 낭독 "닫기"', (tester) async {
      usePenFrame(tester);
      await pumpHost(tester);
      await open(tester);

      final close = find.byType(IconButton);
      expect(tester.getRect(close), const Rect.fromLTWH(304, 44, 48, 48));
      final icon = tester.widget<Icon>(find.descendant(of: close, matching: find.byIcon(AppIcons.x)));
      expect((icon.size, icon.color), (24, AppColors.onInk));
      expect(find.byTooltip('닫기'), findsOneWidget);
    });

    testWidgets('안내 `g3uTN` — "두 손가락으로 크게 볼 수 있어요" 12/normal 흰색 80%(#FFFFFFCC) 가운데 정렬, 하단', (tester) async {
      usePenFrame(tester);
      await pumpHost(tester);
      await open(tester);

      final text = tester.widget<Text>(find.text(_guide));
      final style = text.style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, const Color(0xCCFFFFFF)));
      expect(text.textAlign, TextAlign.center);
      final rect = tester.getRect(find.text(_guide));
      expect(rect.center.dx, closeTo(180, 0.5));
      // 사진 아래 · 화면 바닥 위. 바닥과의 간격은 pen 값표에 숫자가 없어 32 로 정했다(대장 확인 대상).
      expect(rect.top, greaterThan(630));
      expect(780 - rect.bottom, 32);
    });

    testWidgets('확대 범위 — 1배 ~ 4배(대장 지시 값)', (tester) async {
      await pumpHost(tester);
      await open(tester);

      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect((viewer.minScale, viewer.maxScale), (1, 4));
    });

    testWidgets('저장 · 공유 같은 다른 버튼이 없다 — 누를 곳은 닫기 하나', (tester) async {
      await pumpHost(tester);
      await open(tester);

      // M3 IconButton 도 안쪽은 ButtonStyleButton 하나다 — 그것 말고 다른 버튼이 없다.
      final viewer = find.byType(PhotoZoomViewer);
      expect(find.descendant(of: viewer, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)), findsOneWidget);
      expect(find.descendant(of: viewer, matching: find.byType(IconButton)), findsOneWidget);
      expect(find.descendant(of: viewer, matching: find.byTooltip('닫기')), findsOneWidget);
    });
  });

  group('닫기', () {
    testWidgets('닫기 버튼을 누르면 닫힌다', (tester) async {
      await pumpHost(tester);
      await open(tester);

      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoZoomViewer), findsNothing);
    });

    testWidgets('사진 밖 바탕을 누르면 닫힌다', (tester) async {
      usePenFrame(tester);
      await pumpHost(tester);
      await open(tester);

      // 사진(y150~630) 위쪽 빈 바탕 — 닫기 버튼과 겹치지 않는 왼쪽.
      await tester.tapAt(const Offset(40, 110));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoZoomViewer), findsNothing);
    });

    testWidgets('사진 위를 누르면 닫히지 않는다', (tester) async {
      usePenFrame(tester);
      await pumpHost(tester);
      await open(tester);

      await tester.tapAt(const Offset(180, 390));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoZoomViewer), findsOneWidget);
    });

    testWidgets('시스템 뒤로가기로 닫힌다', (tester) async {
      await pumpHost(tester);
      await open(tester);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoZoomViewer), findsNothing);
      expect(find.text('열기'), findsOneWidget);
    });
  });

  group('모션 — 열고 닫을 때 투명도만(standard 220ms)', () {
    double viewerOpacity(WidgetTester tester) => tester
        .widget<FadeTransition>(find.ancestor(of: find.byType(PhotoZoomViewer), matching: find.byType(FadeTransition)).first)
        .opacity
        .value;

    testWidgets('열 때 standard 동안 투명 → 불투명으로 바뀌고, 닫을 때 같은 시간에 사라진다', (tester) async {
      await pumpHost(tester);
      await tester.tap(find.text('열기'));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);

      expect(viewerOpacity(tester), inExclusiveRange(0, 1));
      await tester.pump(AppMotion.standard ~/ 2);
      expect(viewerOpacity(tester), 1);

      await tester.tap(find.byTooltip('닫기'));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      expect(viewerOpacity(tester), inExclusiveRange(0, 1));
      // 끝 시각(정확히 220)에는 아직 0 인 채 남고 그다음 프레임에 빠진다 — standard 를 넘겨 한 번 더 잰다.
      await tester.pump(AppMotion.standard);
      expect(find.byType(PhotoZoomViewer), findsNothing);
    });

    testWidgets('동작 줄이기(disableAnimations)면 바로 열리고 바로 닫힌다', (tester) async {
      await pumpHost(tester, disableAnimations: true);
      await tester.tap(find.text('열기'));
      await tester.pump();

      expect(viewerOpacity(tester), 1);
      final barrier = tester.widget<ModalBarrier>(find.byType(ModalBarrier).last);
      expect(barrier.color, const Color(0xE6222222));

      await tester.tap(find.byTooltip('닫기'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(PhotoZoomViewer), findsNothing);
    });
  });

  group('안내 숨김 — 확대가 1배를 넘으면 거두고 다시 띄우지 않는다(깜빡임 없게)', () {
    double guideOpacity(WidgetTester tester) =>
        tester.widget<AnimatedOpacity>(find.ancestor(of: find.text(_guide), matching: find.byType(AnimatedOpacity))).opacity;

    Future<void> pinch(WidgetTester tester, {required double spread}) async {
      const center = Offset(180, 390);
      final first = await tester.startGesture(center - const Offset(30, 0));
      final second = await tester.startGesture(center + const Offset(30, 0), pointer: 2);
      await tester.pump();
      for (var step = 0; step < 5; step++) {
        await first.moveBy(Offset(-spread / 5, 0));
        await second.moveBy(Offset(spread / 5, 0));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
    }

    testWidgets('처음엔 보이고, 두 손가락으로 벌리면 사라지고, 다시 오므려 1배로 와도 다시 뜨지 않는다 · 뷰어는 열린 채', (tester) async {
      usePenFrame(tester);
      await pumpHost(tester);
      await open(tester);
      expect(guideOpacity(tester), 1);

      await pinch(tester, spread: 60);
      expect(guideOpacity(tester), 0);
      expect(find.byType(PhotoZoomViewer), findsOneWidget, reason: '두 손가락 벌리기는 바탕 누르기가 아니다');

      // 두 손가락 간격 60 → 20 으로 오므린다(1배 밑으로는 안 내려가 1배에 멈춘다).
      await pinch(tester, spread: -20);
      expect(guideOpacity(tester), 0);
    });
  });

  group('접근성', () {
    testWidgets('뷰어가 열리면 화면 읽기가 사진 순번을 읽는다(경로 이름 "사진 N 크게 보기")', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHost(tester, index: 1);
      await open(tester);

      expect(
        find.bySemanticsLabel('사진 2 크게 보기'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('사진 2 크게 보기')),
        isSemantics(label: '사진 2 크게 보기', namesRoute: true, scopesRoute: true),
      );
      expect(tester.getSemantics(find.byType(IconButton)), isSemantics(tooltip: '닫기', isButton: true, hasTapAction: true));
      semantics.dispose();
    });

    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('글자 배율 $scale — 안내가 잘리지 않고 넘치지 않는다', (tester) async {
        usePenFrame(tester);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpHost(tester);
        await open(tester);

        expect(tester.takeException(), isNull);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(_guide), matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.getMaxIntrinsicHeight(paragraph.constraints.maxWidth), lessThanOrEqualTo(paragraph.size.height + 0.5));
        expect(tester.getRect(find.text(_guide)).bottom, lessThanOrEqualTo(780));
      });
    }
  });
}
