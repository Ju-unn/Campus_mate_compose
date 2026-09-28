import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/safety/view/contact_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_contact_blocks.dart';

/// ContactRow 마스터(pen `s3a2m`): 312×60, 간격 12, 아래 선 hairline-soft, 아바타 36(`s4Udw`), 이름 16/600 · 번호 14/400.
void main() {
  Future<void> pump(WidgetTester tester, ContactRow row) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 312, child: row))),
    ));
  }

  Finder box(Color color) => find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration is BoxDecoration && (widget.decoration as BoxDecoration).color == color,
      );

  testWidgets('selectable row is 60 high, avatar 36 with the first letter, name and number', (tester) async {
    await pump(tester, ContactRow(name: '김지은', number: '010-****-2841', selected: false, onTap: () {}));

    expect(tester.getSize(find.byType(ContactRow)), const Size(312, 60));
    expect(find.text('김'), findsOneWidget);
    final avatar = find.ancestor(of: find.text('김'), matching: find.byType(Container)).first;
    expect(tester.getSize(avatar), const Size(36, 36));
    expect(tester.getRect(find.text('김지은')).left - tester.getRect(avatar).right, 12);
    expect(tester.widget<Text>(find.text('김지은')).style?.fontSize, 16);
    expect(tester.widget<Text>(find.text('김지은')).style?.fontWeight, FontWeight.w600);
    expect(maskedNumber('010-****-2841'), findsOneWidget);
    expect(tester.widget<Text>(find.text('2841')).style?.color, AppColors.muted);
    expect(tester.widget<Text>(find.text('2841')).style?.fontSize, 14);
  });

  testWidgets('checkbox off is a white box with an outline, on is primary with a check (pen zlg4q · ORl5o)', (tester) async {
    await pump(tester, ContactRow(name: '김지은', number: '010-****-2841', selected: false, onTap: () {}));
    expect(find.byIcon(AppIcons.check), findsNothing);
    final off = tester.widget<Container>(box(AppColors.canvas));
    expect((off.decoration! as BoxDecoration).border, Border.all(color: AppColors.outline));

    await pump(tester, ContactRow(name: '김지은', number: '010-****-2841', selected: true, onTap: () {}));
    final on = find.ancestor(of: find.byIcon(AppIcons.check), matching: box(AppColors.primary));
    expect(tester.getSize(on), const Size(24, 24));
    expect(tester.getSize(find.byIcon(AppIcons.check)), const Size(16, 16));
    expect(tester.getRect(on).right, tester.getRect(find.byType(ContactRow)).right);
  });

  testWidgets('tapping a selectable row calls onTap', (tester) async {
    var taps = 0;
    await pump(tester, ContactRow(name: '김지은', number: '010-****-2841', selected: false, onTap: () => taps++));

    await tester.tap(find.byType(ContactRow));

    expect(taps, 1);
  });

  testWidgets('removable row has trash and no checkbox, trash calls onRemove', (tester) async {
    var removes = 0;
    await pump(tester, ContactRow(name: '김지은', number: '010-****-2841', onRemove: () => removes++));

    expect(find.byIcon(AppIcons.check), findsNothing);
    expect(box(AppColors.canvas), findsNothing);
    await tester.tap(find.byIcon(AppIcons.trash2));

    expect(removes, 1);
  });

  testWidgets('row without an initial draws an empty avatar', (tester) async {
    await pump(tester, ContactRow(name: '이전에 차단한 연락처', number: '이 기기에서 이름을 찾을 수 없어요', showInitial: false, onRemove: () {}));

    expect(find.text('이'), findsNothing);
  });
}
