import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:campus_mate/profile/traits/view/choice_pickers.dart';
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: child)),
      ),
    );
  }

  Color fillOf(WidgetTester tester, String label) {
    final ink = tester.widget<Ink>(find.ancestor(of: find.text(label), matching: find.byType(Ink)).first);
    return (ink.decoration! as BoxDecoration).color!;
  }

  // 칸 글자는 pen 이 전부 16/600 이다 — SmokeToggle 마스터 `Y1TDq2` 칸 글자(`i5Y2r` · `Y0WfHq`) 16/600 자간 -0.16 #222222,
  // 05-11 `Xmttw` · 컴포넌트 `juWlH` · 05-10 종교 `sCsQf` · 15-6 `mhdYA` · `N5B0rW` · `U4f5Q` · `Q1UbA` · `ZuPTD` 도 같다(18/700 은 없다).
  // 종전 앱은 AppTypography.label(18/700)이었다. 고른 칸도 안 고른 칸도 같은 글자다.
  group('ChoiceCell 글자(pen 16/600)', () {
    void expectPenLabelStyle(WidgetTester tester, String label) {
      final style = tester.widget<Text>(find.text(label)).style!;
      expect((style.fontSize, style.fontWeight, style.color), (16, FontWeight.w600, AppColors.ink), reason: label);
      expect(style.letterSpacing, closeTo(-0.16, 0.001), reason: label);
    }

    testWidgets('흡연 두 칸 — 고른 칸도 안 고른 칸도 16/600 자간 -0.16 #222222', (tester) async {
      await pumpIn(tester, SmokePicker(isSmoker: true, onSelected: (_) {}));

      expectPenLabelStyle(tester, '한다');
      expectPenLabelStyle(tester, '안 한다');
    });

    testWidgets('종교 네 칸도 같다', (tester) async {
      await pumpIn(tester, ReligionPicker(selected: Religion.catholic, onSelected: (_) {}));

      for (final label in ['무교', '기독교', '천주교', '불교']) {
        expectPenLabelStyle(tester, label);
      }
    });

    testWidgets('이상형 조건의 흡연하는 사람 두 칸도 같다', (tester) async {
      await pumpIn(tester, AcceptsSmokerPicker(acceptsSmoker: false, onSelected: (_) {}));

      expectPenLabelStyle(tester, '싫어요');
      expectPenLabelStyle(tester, '상관없어요');
    });

    testWidgets('글자 1.5배 · 폭 360 에서도 칸(높이 56) 안에서 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpIn(
        tester,
        Column(
          children: [
            ReligionPicker(selected: null, onSelected: (_) {}),
            AcceptsSmokerPicker(acceptsSmoker: null, onSelected: (_) {}),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      for (final label in ['무교', '기독교', '천주교', '불교', '싫어요', '상관없어요']) {
        final cell = tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(Ink)).first);
        expect(cell.height, 56, reason: label);
        expect(cell.contains(tester.getRect(find.text(label)).topLeft), isTrue, reason: label);
        expect(cell.contains(tester.getRect(find.text(label)).bottomRight), isTrue, reason: label);
      }
    });
  });

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

  // 앱 1.0.2 — 06-1 "흡연하는 사람" 두 칸(pen `Mg9O3` = SmokeToggle `Y1TDq2` 의 줄만): 왼쪽 싫어요(false) · 오른쪽 상관없어요(true).
  group('AcceptsSmokerPicker', () {
    testWidgets('싫어요 · 상관없어요 두 칸, 높이 56 · 사이 12(312×56), 왼쪽이 싫어요', (tester) async {
      await pumpIn(tester, AcceptsSmokerPicker(acceptsSmoker: true, onSelected: (_) {}));

      expect(tester.getRect(find.byType(AcceptsSmokerPicker)).size, const Size(312, 56));
      final no = tester.getRect(find.ancestor(of: find.text('싫어요'), matching: find.byType(Ink)).first);
      final any = tester.getRect(find.ancestor(of: find.text('상관없어요'), matching: find.byType(Ink)).first);
      expect(no.size, const Size(150, 56));
      expect(any.left - no.right, 12);
    });

    testWidgets('상관없어요(true)면 오른쪽 칸만, 싫어요(false)면 왼쪽 칸만 켜진다', (tester) async {
      await pumpIn(tester, AcceptsSmokerPicker(acceptsSmoker: true, onSelected: (_) {}));
      expect(fillOf(tester, '상관없어요'), AppColors.primaryWash);
      expect(fillOf(tester, '싫어요'), AppColors.surfaceSoft);

      await pumpIn(tester, AcceptsSmokerPicker(acceptsSmoker: false, onSelected: (_) {}));
      expect(fillOf(tester, '싫어요'), AppColors.primaryWash);
      expect(fillOf(tester, '상관없어요'), AppColors.surfaceSoft);
    });

    testWidgets('안 고른 상태(null)면 두 칸 다 꺼져 있다', (tester) async {
      await pumpIn(tester, AcceptsSmokerPicker(acceptsSmoker: null, onSelected: (_) {}));

      expect(fillOf(tester, '싫어요'), AppColors.surfaceSoft);
      expect(fillOf(tester, '상관없어요'), AppColors.surfaceSoft);
    });

    testWidgets('누르면 싫어요는 false, 상관없어요는 true 를 돌려준다', (tester) async {
      final picked = <bool>[];
      await pumpIn(tester, AcceptsSmokerPicker(acceptsSmoker: true, onSelected: picked.add));

      await tester.tap(find.text('싫어요'));
      await tester.tap(find.text('상관없어요'));

      expect(picked, [false, true]);
    });
  });
}
