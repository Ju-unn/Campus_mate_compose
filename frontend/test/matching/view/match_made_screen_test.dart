import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
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

  group('매칭 성사 등장(DESIGN §7 emphasis — 하루 두 번 중 하나)', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: MatchMadeScreen(nickname: '토끼'))),
        );

    Entrance entranceOf(WidgetTester tester, Finder child) =>
        tester.widget<Entrance>(find.ancestor(of: child, matching: find.byType(Entrance)));

    testWidgets('마스코트는 0.92 → 1 · 투명 → 불투명 420ms(emphasis 커브는 크기에만)', (tester) async {
      await pump(tester);

      final mascot = entranceOf(tester, find.byType(Image));
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
