import 'package:campus_mate/chat/view/bubble_report_menu.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('팝업(pen afUag) 그림자는 popover, 아이콘은 3D 사이렌 22 · 글자와 12', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: BubbleReportMenu(onReport: () {})))));

    final card = tester.widget<Container>(
      find.descendant(of: find.byType(BubbleReportMenu), matching: find.byType(Container)).first,
    );
    expect((card.decoration! as BoxDecoration).boxShadow, AppElevation.popover);
    final icon = find.byType(Icon3d);
    expect(tester.widget<Icon3d>(icon).icon, AppIcon3d.siren);
    expect(tester.getSize(icon), const Size(22, 22));
    expect(tester.getTopLeft(find.text('이 메시지 신고')).dx - tester.getTopRight(icon).dx, 12);
  });
}
