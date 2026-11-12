import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/view/home_grid.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// pen 홈 v3 초안 `kkKiZ`(11-12) — HomeTileGrid `C3J23d` 에서 숫자 3칸 줄 `X5WJO` · 곧 열려요 `gzY4Z` 를 빼고
/// 이벤트 칸을 에브리타임으로 바꾼 2칸 한 줄. 링크 칸 마스터 `F4rC8g`. 홈 본문 폭 328 안에 둔다.
void main() {
  late int instagramTaps;
  late int everytimeTaps;

  setUp(() {
    instagramTaps = 0;
    everytimeTaps = 0;
  });

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: HomeGrid(onInstagram: () => instagramTaps++, onEverytime: () => everytimeTaps++),
            ),
          ),
        ),
      ),
    );
  }

  const labels = ['인스타그램', '에브리타임'];
  Finder tileOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(Material)).first;
  Finder plateIn(Finder tile) => find.descendant(of: tile, matching: find.byType(IconPlate));

  testWidgets('2칸 한 줄 — 반반(160) · 사이 8 · 높이 80 · 전체 328×80', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.byType(HomeGrid)), const Size(328, 80));
    final instagram = tester.getRect(tileOf('인스타그램'));
    final everytime = tester.getRect(tileOf('에브리타임'));
    expect(instagram.topLeft, tester.getTopLeft(find.byType(HomeGrid)));
    expect(instagram.size, const Size(160, 80));
    expect(everytime.size, const Size(160, 80));
    expect(everytime.left - instagram.right, 8);
    expect(everytime.right, 16 + 328);
  });

  testWidgets('숫자 3칸 · 이벤트 · 곧 열려요 칸은 없다', (tester) async {
    await pump(tester);

    for (final gone in ['전달된 카드', '가입 수', '시작된 대화', '이벤트', '곧 열려요']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.byIcon(AppIcons.hourglass), findsNothing);
  });

  testWidgets('그림 원 — 두 칸에 하나씩, 40 원 · surfaceSoft 채움 · 테두리 · 그림자 없음', (tester) async {
    await pump(tester);

    expect(find.byType(IconPlate), findsNWidgets(2));
    for (final plate in tester.widgetList<IconPlate>(find.byType(IconPlate))) {
      final finder = find.byWidget(plate);
      final box = tester.widget<Container>(find.descendant(of: finder, matching: find.byType(Container)).first).decoration!
          as BoxDecoration;
      expect(tester.getSize(finder), const Size(40, 40));
      expect(box.color, AppColors.surfaceSoft);
      expect(box.shape, BoxShape.circle);
      expect(box.border, isNull);
      expect(box.boxShadow, isNull);
    }
  });

  testWidgets('링크 칸 `F4rC8g` — canvas · hairline 1 안쪽 테두리 · 바깥 그림자 homeTileRaised', (tester) async {
    await pump(tester);

    for (final label in labels) {
      final tile = tileOf(label);
      final face = tester.widget<Material>(tile);
      expect(face.color, AppColors.canvas, reason: label);
      expect(
        face.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.hairline)),
        reason: label,
      );
      final shade = find.ancestor(of: tile, matching: find.byType(DecoratedBox)).first;
      final decoration = tester.widget<DecoratedBox>(shade).decoration as BoxDecoration;
      expect(decoration.boxShadow, AppElevation.homeTileRaised, reason: label);
      expect(decoration.borderRadius, BorderRadius.circular(14), reason: label);
      expect(tester.getRect(shade), tester.getRect(tile), reason: label);
    }
  });

  testWidgets('링크 칸 속 — 로고 28 이 그림 원 40 가운데 → 6 → 라벨 12/600 ink lh1.4, 세로 가운데', (tester) async {
    await pump(tester);

    for (final (label, asset) in [
      ('인스타그램', 'assets/images/brand-instagram-v1.webp'),
      ('에브리타임', 'assets/images/brand-everytime-v1.webp'),
    ]) {
      final tile = tileOf(label);
      final logo = find.descendant(of: tile, matching: find.byType(Image));
      expect((tester.widget<Image>(logo).image as AssetImage).assetName, asset, reason: label);
      expect(tester.widget<Image>(logo).fit, BoxFit.contain, reason: label);
      expect(tester.getSize(logo), const Size(28, 28), reason: label);
      expect(tester.getCenter(logo), tester.getCenter(plateIn(tile)), reason: label);

      final plate = tester.getRect(plateIn(tile));
      final text = tester.getRect(find.text(label));
      expect(plate.top - tester.getRect(tile).top, closeTo(tester.getRect(tile).bottom - text.bottom, 0.01), reason: label);
      expect(plate.center.dx, tester.getCenter(tile).dx, reason: label);
      expect(text.top, closeTo(plate.bottom + 6, 0.01), reason: label);
      expect(
        tester.widget<Text>(find.text(label)).style,
        AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 1.4, color: AppColors.ink),
        reason: label,
      );
    }
  });

  testWidgets('링크 칸 오른쪽 위 화살표 칩 — 20 원 primaryWash · 위 6 오른쪽 6 · 안에 arrow-up-right 12 primaryText', (tester) async {
    await pump(tester);

    for (final label in labels) {
      final tile = tileOf(label);
      final arrow = find.descendant(of: tile, matching: find.byIcon(AppIcons.arrowUpRight));
      expect((tester.widget<Icon>(arrow).size, tester.widget<Icon>(arrow).color), (12.0, AppColors.primaryText), reason: label);
      final chip = find.ancestor(of: arrow, matching: find.byType(Container)).first;
      final box = tester.widget<Container>(chip).decoration! as BoxDecoration;
      expect((box.color, box.shape), (AppColors.primaryWash, BoxShape.circle), reason: label);
      final rect = tester.getRect(chip);
      final tileRect = tester.getRect(tile);
      expect(rect.size, const Size(20, 20), reason: label);
      expect((rect.top - tileRect.top, tileRect.right - rect.right), (6, 6), reason: label);
    }
  });

  testWidgets('두 칸은 칸 전체(모서리 끝까지)가 눌리고 각자 부른다', (tester) async {
    await pump(tester);

    await tester.tapAt(tester.getBottomRight(tileOf('인스타그램')) - const Offset(6, 6));
    await tester.tapAt(tester.getTopLeft(tileOf('에브리타임')) + const Offset(6, 6));
    await tester.pump();

    expect((instagramTaps, everytimeTaps), (1, 1));
  });

  testWidgets('눌림 잉크는 칸 자기 Material 에 그린다(COMMON 4-2) · 누름 칸 160×80', (tester) async {
    await pump(tester);

    for (final label in labels) {
      final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      final painter = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(painter), tester.getSize(ink), reason: label);
      expect(tester.getSize(ink), const Size(160, 80), reason: label);
    }
  });

  testWidgets('낭독기 — 두 칸 모두 버튼, "CampusMate 인스타그램 열기" · "에브리타임 열기"', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    for (final (label, spoken) in [('인스타그램', 'CampusMate 인스타그램 열기'), ('에브리타임', '에브리타임 열기')]) {
      final data = tester.getSemantics(find.text(label)).getSemanticsData();
      expect(data.label, spoken, reason: label);
      expect(data.flagsCollection.isButton, isTrue, reason: label);
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
    }
    handle.dispose();
  });

  for (final scale in [1.5, 2.0]) {
    testWidgets('글자 $scale 배 — 넘치지 않고 라벨이 칸에 잘리지 않으며 칸이 늘어난다', (tester) async {
      await pump(tester, textScale: scale);

      expect(tester.takeException(), isNull);
      final clipped = [
        for (final element in find.descendant(of: find.byType(HomeGrid), matching: find.byType(RichText)).evaluate())
          if (element.renderObject case final RenderParagraph p
              when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                  p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
            p.text.toPlainText(),
      ];
      expect(clipped, isEmpty);
      for (final label in labels) {
        final ownerRect = tester.getRect(tileOf(label));
        final textRect = tester.getRect(find.text(label));
        expect(ownerRect.contains(textRect.topLeft) && ownerRect.contains(textRect.bottomRight - const Offset(0.01, 0.01)), isTrue,
            reason: '$label 가 칸 안에 있다');
        expect(ownerRect.height, greaterThanOrEqualTo(80), reason: label);
      }
    });
  }
}
