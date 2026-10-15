import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/tour/view/coach_line.dart';
import 'package:campus_mate/tour/view/coach_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hole = Rect.fromLTWH(14, 70, 332, 164);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: Center(child: child)),
      );

  testWidgets('pen tFIey — 덮개는 검정 알파 B3 를 화면 전체에 칠하고 구멍만 비우며(evenodd), 구멍 바깥에 primary 2 테두리', (tester) async {
    await pump(tester, const SizedBox(width: 360, height: 740, child: CoachOverlay(hole: hole, radius: 34)));

    expect(
      find.byType(CoachOverlay),
      paints
        ..path(
          color: const Color(0xB3000000),
          includes: const [Offset(1, 1), Offset(359, 590)],
          excludes: [hole.center],
        )
        ..rrect(
          rrect: RRect.fromRectAndRadius(hole.inflate(1), const Radius.circular(35)),
          color: AppColors.primary,
          strokeWidth: 2,
          style: PaintingStyle.stroke,
        ),
    );
  });

  testWidgets('구멍이 없으면(5단계 가운데 카드) 덮개만 칠하고 테두리는 없다', (tester) async {
    await pump(tester, const SizedBox(width: 360, height: 740, child: CoachOverlay(hole: null, radius: 16)));

    expect(
      find.byType(CoachOverlay),
      paints..path(color: const Color(0xB3000000), includes: const [Offset(180, 370)]),
    );
    expect(find.byType(CoachOverlay), isNot(paints..rrect()));
  });

  testWidgets('pen h1gWg(점 위) — 흰 점 10 이 위 끝, 흰 선 1.5 가 아래로 끝까지', (tester) async {
    await pump(tester, const CoachLine(length: 32, dotAtTop: true, progress: 1));

    expect(tester.getSize(find.byType(CoachLine)), const Size(10, 32));
    expect(
      find.byType(CoachLine),
      paints
        ..line(p1: const Offset(5, 5), p2: const Offset(5, 32), strokeWidth: 1.5, color: AppColors.canvas)
        ..circle(x: 5, y: 5, radius: 5, color: AppColors.canvas),
    );
  });

  testWidgets('pen c4jwKG(점 아래) — 점이 아래 끝, 선은 점에서 위로 [progress] 만큼 자란다', (tester) async {
    await pump(tester, const CoachLine(length: 32, dotAtTop: false, progress: 0.5));

    expect(
      find.byType(CoachLine),
      paints
        ..line(p1: const Offset(5, 27), p2: const Offset(5, 27 - 27 * 0.5), strokeWidth: 1.5)
        ..circle(x: 5, y: 27, radius: 5),
    );
  });
}
