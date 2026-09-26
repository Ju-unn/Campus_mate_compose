import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/profile/view/survey_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// pen 05-01~05-09 의 질문과 줄바꿈 자리(erd3 2026-09-26).
const List<String> _headlines = [
  '밖에 나가서 활동하는 걸\n좋아하시나요?',
  '낯선 사람과 빨리\n친해지는 편인가요?',
  '미리 계획을\n세우는 편인가요?',
  '연애할 때 연락을\n자주 하는 편인가요?',
  '감정 표현이\n풍부한 편인가요?',
  '술자리를\n즐기는 편인가요?',
  '운동을 꾸준히\n하는 편인가요?',
  '마음이 확실하면 관계를\n빠르게 진전시키나요?',
  '새로운 걸 시도하는 걸\n좋아하시나요?',
];

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SurveyScreen())),
    );
  }

  Future<void> next(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
    }
  }

  Color fillOf(WidgetTester tester, String label) {
    final ink = tester.widget<Ink>(
      find.ancestor(of: find.text(label), matching: find.byType(Ink)).first,
    );
    return (ink.decoration! as BoxDecoration).color!;
  }

  testWidgets('슬라이더를 건드리지 않아도 가운데가 골라져 있어 다음으로 넘어간다', (tester) async {
    // pen `mkf89` 는 가운데 점이 골라진 채로 열린다(2026-09-26 사용자 결정) —
    // 아무 쪽도 아닌 사람은 건드리지 않고 그대로 지나갈 수 있어야 한다.
    await pump(tester);

    await next(tester, 1);

    expect(find.text(_headlines[1]), findsOneWidget);
  });

  testWidgets('9개 질문은 pen 이 정한 자리에서 줄이 끊긴다', (tester) async {
    // 기기 폭에 맡기면 두 줄이 어디서 끊길지 매번 달라진다.
    await pump(tester);

    for (final headline in _headlines) {
      expect(find.text(headline), findsOneWidget);
      await next(tester, 1);
    }
  });

  testWidgets('종교·흡연 칸 바탕은 다른 회색 칸과 같은 #F7F7F7 이다', (tester) async {
    // pen `Rmfti`·`Y1TDq2` 가 #E5E5E5(비활성 채움)에서 표면 회색으로 바뀌었다 —
    // 종전 값은 고를 수 있는 칸인데 꺼진 버튼처럼 보였다.
    await pump(tester);

    await next(tester, 9);
    expect(fillOf(tester, '무교'), AppColors.surfaceSoft);

    // 종교는 기본 선택이 없다 — 골라야 "다음" 이 켜진다.
    await tester.tap(find.text('무교'));
    await tester.pump();
    await next(tester, 1);

    expect(fillOf(tester, '한다'), AppColors.surfaceSoft);
  });

  testWidgets('종교·흡연 칸 눌림 효과는 화면이 아니라 칸이 그린다', (tester) async {
    // 눌림 효과는 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 스크롤해도 테두리만 떠 있다(COMMON §4-2).
    await pump(tester);
    await next(tester, 9);

    final text = find.text('무교');
    final cell = find.ancestor(of: text, matching: find.byType(InkWell)).first;
    final painter = find.ancestor(of: text, matching: find.byType(Material)).first;

    expect(tester.getSize(painter), tester.getSize(cell));
  });
}
