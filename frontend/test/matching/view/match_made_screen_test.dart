import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_lottie_view.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/view/match_made_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('상대 닉네임을 넣은 두 줄 서브텍스트를 보여준다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
    );

    expect(find.text('매칭됐어요!'), findsOneWidget);
    expect(find.text('토끼 님과 매칭됐어요.\n대화를 시작해 보세요.'), findsOneWidget);
    expect(find.text('나중에 확인하기'), findsOneWidget);
  });

  // pen 12 `jqqaz` (대장 전달): 옛 마스코트 `c9GZFr` 자리를 Lottie 300×250 으로, 가로 가운데 y115. 그 아래 24 → 제목 → 12 → 설명 → 40 → 버튼 → 12 → 나중에 확인하기.
  group('성사 연출(pen jqqaz)', () {
    Future<void> pump360x780(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('옛 마스코트 사진은 없고, 성사 연출(matchCelebration)이 그 자리에 있다', (tester) async {
      await pump360x780(tester);

      expect(find.byType(Image), findsNothing);
      expect(tester.widget<AppLottieView>(find.byType(AppLottieView)).scene, AppLottie.matchCelebration);
    });

    testWidgets('300×250 · 가로 가운데 · 화면 위에서 115', (tester) async {
      await pump360x780(tester);

      final rect = tester.getRect(find.byType(AppLottieView));
      expect(rect.size, const Size(300, 250));
      expect(rect.center.dx, 180);
      expect(rect.top, closeTo(115, 1));
    });

    testWidgets('연출은 장식이라 낭독기에서 빼고, 아래로 24 → 제목 · 12 → 설명 · 40 → 버튼 · 12 → 나중에 확인하기', (tester) async {
      await pump360x780(tester);

      expect(tester.widget<AppLottieView>(find.byType(AppLottieView)).semanticLabel, isNull);
      final lottie = tester.getRect(find.byType(AppLottieView));
      final title = tester.getRect(find.text('매칭됐어요!'));
      final body = tester.getRect(find.text('토끼 님과 매칭됐어요.\n대화를 시작해 보세요.'));
      final start = tester.getRect(find.widgetWithText(AppButton, '대화 시작하기'));
      final later = tester.getRect(find.widgetWithText(AppButton, '나중에 확인하기'));
      expect(title.top - lottie.bottom, 24);
      expect(body.top - title.bottom, 12);
      expect(start.top - body.bottom, 40);
      expect(later.top - start.bottom, 12);
    });

    // 12 는 배경이 아니라 본문 안 그림이라 안전 영역(상태 표시줄 40 · 홈 막대 20) 안에서 가운데다:
    // 40 + (720 - 아래 여백 18 - 내용 532) / 2 = 125 — 안전 영역이 없을 때(y115)보다 10 아래다.
    testWidgets('상태 표시줄 40 · 홈 막대 20 이 있으면 연출은 안전 영역 안에서 가운데(y125)에 서고 버튼은 홈 막대를 넘지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 20);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
      );
      await tester.pumpAndSettle();

      final lottie = tester.getRect(find.byType(AppLottieView));
      expect(lottie.top, closeTo(125, 1));
      expect(lottie.top, greaterThanOrEqualTo(40));
      expect(tester.getRect(find.widgetWithText(AppButton, '나중에 확인하기')).bottom, lessThanOrEqualTo(780 - 20));
    });

    // pen 원본 12 `UFNSi` 의 "매칭됐어요!"(`T5kQ4x`)도 32/700 이다(대장 확인 2026-11-03) — 앱 토큰 display(32/700, 매칭 성사 화면 용도).
    testWidgets('제목 "매칭됐어요!" 는 display 32/700 ink', (tester) async {
      await pump360x780(tester);

      final style = tester.widget<Text>(find.text('매칭됐어요!')).style!;
      expect(style, AppTypography.display.copyWith(color: AppColors.ink));
      expect((style.fontSize, style.fontWeight), (32.0, FontWeight.w700));
    });

    // CLAUDE.md 규칙 3(dp 는 화면 비율에 대응): 고정 300×250 장면이 좁은 화면에서 잘리지 않게 쓸 수 있는 폭(좌우 16 뺀 값)에 맞춰 비율 그대로 줄인다.
    testWidgets('320 폭에서는 쓸 수 있는 폭 288 에 맞춰 비율 그대로 줄어(288×240) 잘리지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
      );
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byType(AppLottieView));
      expect(rect.size, const Size(288, 240));
      expect(rect.center.dx, 160);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    });

    testWidgets('작은 화면 · 글자 2배에서는 넘치지 않고 스크롤로 닿는다', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('나중에 확인하기'), 100);
      expect(find.text('나중에 확인하기'), findsOneWidget);
    });
  });

  group('매칭 성사 등장(DESIGN §7 emphasis — 하루 두 번 중 하나)', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
        );

    Entrance entranceOf(WidgetTester tester, Finder child) =>
        tester.widget<Entrance>(find.ancestor(of: child, matching: find.byType(Entrance)));

    testWidgets('성사 연출은 0.92 → 1 · 투명 → 불투명 420ms(emphasis 커브는 크기에만)', (tester) async {
      await pump(tester);

      final mascot = entranceOf(tester, find.byType(AppLottieView));
      expect(
        (mascot.scaleFrom, mascot.rise, mascot.duration, mascot.curve, mascot.delay),
        (0.92, 0.0, AppMotion.emphasis, AppMotion.emphasisCurve, Duration.zero),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('제목 · 부제는 120ms 뒤 아래 12 에서 standard 로 올라온다', (tester) async {
      await pump(tester);

      for (final text in ['매칭됐어요!', '토끼 님과 매칭됐어요.\n대화를 시작해 보세요.']) {
        final entrance = entranceOf(tester, find.text(text));
        expect(
          (entrance.rise, entrance.delay, entrance.duration, entrance.curve),
          (12.0, const Duration(milliseconds: 120), AppMotion.standard, AppMotion.standardCurve),
          reason: text,
        );
      }
      await tester.pumpAndSettle();
    });

    testWidgets('버튼은 움직이지 않고 처음부터 누를 수 있다', (tester) async {
      await pump(tester);

      expect(find.ancestor(of: find.byType(AppButton), matching: find.byType(Entrance)), findsNothing);
      await tester.pumpAndSettle();
    });
  });
}
