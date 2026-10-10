import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/view/choice_pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 종교 · 흡연 칸 고르기 — 05-10 · 05-11(성향 설문)과 15-6 기본 정보 수정이 같이 쓴다(pen `KT7Lu` · `juWlH`).
void main() {
  Future<void> pumpIn(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: child)),
      ),
    );
  }

  Color fillOf(WidgetTester tester, String label) {
    final ink = tester.widget<Ink>(find.ancestor(of: find.text(label), matching: find.byType(Ink)).first);
    return (ink.decoration! as BoxDecoration).color!;
  }

  group('ReligionPicker', () {
    testWidgets('2x2 · 칸 높이 56 · 칸 사이 12 — 무교 · 기독교 / 천주교 · 불교(pen `KT7Lu` 312×124)', (tester) async {
      await pumpIn(tester, ReligionPicker(selected: null, onSelected: (_) {}));

      expect(tester.getRect(find.byType(ReligionPicker)).size, const Size(312, 124));
      final none = tester.getRect(find.ancestor(of: find.text('무교'), matching: find.byType(Ink)).first);
      final protestant = tester.getRect(find.ancestor(of: find.text('기독교'), matching: find.byType(Ink)).first);
      final catholic = tester.getRect(find.ancestor(of: find.text('천주교'), matching: find.byType(Ink)).first);
      expect(none.size, const Size(150, 56));
      expect(protestant.left - none.right, 12);
      expect(catholic.top - none.bottom, 12);
    });

    testWidgets('고른 칸만 분홍 워시, 나머지는 surface-soft', (tester) async {
      await pumpIn(tester, ReligionPicker(selected: Religion.catholic, onSelected: (_) {}));

      expect(fillOf(tester, '천주교'), AppColors.primaryWash);
      expect(fillOf(tester, '무교'), AppColors.surfaceSoft);
    });

    testWidgets('누르면 그 종교를 돌려준다', (tester) async {
      Religion? picked;
      await pumpIn(tester, ReligionPicker(selected: null, onSelected: (religion) => picked = religion));

      await tester.tap(find.text('불교'));

      expect(picked, Religion.buddhist);
    });
  });

  group('SmokePicker', () {
    testWidgets('한다 · 안 한다 두 칸, 높이 56 · 사이 12(pen `juWlH` 312×56)', (tester) async {
      await pumpIn(tester, SmokePicker(isSmoker: null, onSelected: (_) {}));

      expect(tester.getRect(find.byType(SmokePicker)).size, const Size(312, 56));
      final yes = tester.getRect(find.ancestor(of: find.text('한다'), matching: find.byType(Ink)).first);
      final no = tester.getRect(find.ancestor(of: find.text('안 한다'), matching: find.byType(Ink)).first);
      expect(yes.size, const Size(150, 56));
      expect(no.left - yes.right, 12);
    });

    testWidgets('안 한다(false)를 고르면 그 칸만 켜진다 — null 과 구분', (tester) async {
      await pumpIn(tester, SmokePicker(isSmoker: false, onSelected: (_) {}));

      expect(fillOf(tester, '안 한다'), AppColors.primaryWash);
      expect(fillOf(tester, '한다'), AppColors.surfaceSoft);
    });

    testWidgets('누르면 true · false 를 돌려준다', (tester) async {
      final picked = <bool>[];
      await pumpIn(tester, SmokePicker(isSmoker: null, onSelected: picked.add));

      await tester.tap(find.text('한다'));
      await tester.tap(find.text('안 한다'));

      expect(picked, [true, false]);
    });
  });
}
