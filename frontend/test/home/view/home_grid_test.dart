import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/home_grid.dart';
import 'package:campus_mate/home/view/stat_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

HomeSummary _summary({int delivered = 1234567, int signups = 862, int conversations = 391}) => HomeSummary(
      deliveredCards: delivered,
      signups: signups,
      conversationsStarted: conversations,
      reviewRating: 4.6,
      reviewCount: 57,
      campuses: const [],
      profileCompletionPercent: 40,
    );

/// pen 홈 6칸 그리드 v2(초안 A, 10-16 사용자 채택) — 화면 인스턴스 `blOdR`(ref HomeTileGrid v2 `R62HQ`),
/// 마스터 통계 칸 `BeClX` · 링크 칸 `F4rC8g` · 곧 열려요 칸 `BoTMl`(Z54et Row Q). 홈 본문 폭 328 안에 둔다.
void main() {
  late int instagramTaps;
  late int eventTaps;

  setUp(() {
    instagramTaps = 0;
    eventTaps = 0;
  });

  Future<void> pump(WidgetTester tester, HomeSummary summary, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: HomeGrid(
                summary: summary,
                onInstagram: () => instagramTaps++,
                onEvent: () => eventTaps++,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder tileOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(Material)).first;
  Finder plateIn(Finder tile) => find.descendant(of: tile, matching: find.byType(IconPlate));
  Finder soonTile() => find.ancestor(of: find.text('곧 열려요'), matching: find.byType(Container)).first;
  Finder statTileOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(StatTile));
  BoxDecoration statFace(WidgetTester tester, Finder tile) =>
      tester.widget<Container>(find.descendant(of: tile, matching: find.byType(Container)).first).decoration! as BoxDecoration;

  testWidgets('3열 × 2행 · 통계 행 112 · 링크 행 80 · 간격 8 · 전체 328×200', (tester) async {
    await pump(tester, _summary());

    expect(tester.getSize(find.byType(HomeGrid)), const Size(328, 200));
    final first = tester.getRect(find.byType(StatTile).at(0));
    expect(first.topLeft, tester.getTopLeft(find.byType(HomeGrid)));
    final second = tester.getRect(find.byType(StatTile).at(1));
    final instagram = tester.getRect(tileOf('인스타그램'));
    expect(first.size, const Size(104, 112));
    expect(second.left - first.right, 8);
    expect(instagram.top - first.bottom, 8);
    expect(instagram.size, const Size(104, 80));
    expect(tester.getSize(tileOf('이벤트')), const Size(104, 80));
    expect(tester.getSize(soonTile()), const Size(104, 80));
    expect(tester.getRect(soonTile()).right, 16 + 328);
  });

  testWidgets('통계 칸 `BeClX` — canvas · 테두리 없음 · 바깥 그림자 homeTileLow((0,1) blur 8 #00000014)', (tester) async {
    await pump(tester, _summary());

    for (final label in ['전달된 카드', '가입 수', '시작된 대화']) {
      final face = statFace(tester, statTileOf(label));
      expect(face.color, AppColors.canvas, reason: label);
      expect(face.border, isNull, reason: label);
      expect(face.boxShadow, AppElevation.homeTileLow, reason: label);
      expect(face.borderRadius, BorderRadius.circular(14), reason: label);
    }
  });

  testWidgets('통계 칸 속 — 그림 자리 44 안 3D 그림 40 → 2 → 숫자 24/700 primaryText 자간 −0.3(33) → 2 → 라벨 12/600 muted(17), 세로 가운데', (tester) async {
    // 칸 폭에 드는 숫자로 본다 — 넓은 숫자는 줄을 바꾸지 않고 칸 안에서 줄어든다(아래 테스트).
    await pump(tester, _summary(delivered: 123));

    for (final (label, value, icon) in [
      ('전달된 카드', '123', AppIcon3d.send),
      ('가입 수', '862', AppIcon3d.join),
      ('시작된 대화', '391', AppIcon3d.chat),
    ]) {
      final tile = statTileOf(label);
      expect(plateIn(tile), findsNothing, reason: label);
      final art = find.descendant(of: tile, matching: find.byType(Icon3d));
      expect((tester.widget<Icon3d>(art).icon, tester.widget<Icon3d>(art).size), (icon, 40.0), reason: label);
      expect(tester.getSize(art), const Size(40, 40), reason: label);
      final slot = tester.getRect(
        find.ancestor(of: art, matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 44 && w.height == 44)),
      );
      final number = tester.getRect(find.text(value));
      final caption = tester.getRect(find.text(label));
      expect(slot.top - tester.getRect(tile).top, 7, reason: label); // (112 − (44 + 2 + 33 + 2 + 17)) / 2
      expect(tester.getCenter(art), slot.center, reason: label);
      expect(slot.center.dx, tester.getCenter(tile).dx, reason: label);
      expect(number.top, slot.bottom + 2, reason: label);
      expect(number.height, 33, reason: label);
      expect(caption.top, number.bottom + 2, reason: label);
      expect(caption.height, 17, reason: label);
      final style = tester.widget<Text>(find.text(value)).style!;
      expect(
        (style.fontSize, style.fontWeight, style.color, style.letterSpacing),
        (24, FontWeight.w700, AppColors.primaryText, -0.3),
        reason: label,
      );
      expect(
        tester.widget<Text>(find.text(label)).style,
        AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 17 / 12, color: AppColors.muted),
        reason: label,
      );
    }
  });

  testWidgets('숫자는 천 단위 쉼표 · 칸보다 넓으면 줄을 바꾸지 않고 칸 안(좌우 4)에서 줄인다', (tester) async {
    await pump(tester, _summary());

    final number = find.text('1,234,567');
    expect(number, findsOneWidget);
    final tile = tester.getRect(find.ancestor(of: number, matching: find.byType(StatTile)));
    expect(tester.getRect(number).width, lessThanOrEqualTo(tile.width - 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('그림 원은 링크 · 곧 열려요 칸 3개에만 — 40 원 · surfaceSoft 채움 · 테두리 없음 · 그림자 없음', (tester) async {
    await pump(tester, _summary());

    expect(find.byType(IconPlate), findsNWidgets(3));
    expect(find.descendant(of: find.byType(StatTile), matching: find.byType(IconPlate)), findsNothing);
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

  testWidgets('0 인 통계 칸은 숨기고 남은 칸이 위 행 폭을 나눈다', (tester) async {
    await pump(tester, _summary(delivered: 0));

    expect(find.text('전달된 카드'), findsNothing);
    final join = tester.getRect(find.byType(StatTile).at(0));
    final chat = tester.getRect(find.byType(StatTile).at(1));
    expect(join.width, 160);
    expect(chat.left - join.right, 8);
  });

  testWidgets('세 통계가 모두 0 이면 위 행만 빠지고 링크 행(80)은 남는다', (tester) async {
    await pump(tester, _summary(delivered: 0, signups: 0, conversations: 0));

    expect(find.byType(StatTile), findsNothing);
    expect(tester.getSize(find.byType(HomeGrid)), const Size(328, 80));
    expect(find.text('인스타그램'), findsOneWidget);
    expect(find.text('이벤트'), findsOneWidget);
    expect(find.text('곧 열려요'), findsOneWidget);
  });

  testWidgets('링크 칸 `F4rC8g` — canvas · hairline 1 안쪽 테두리 · 바깥 그림자 homeTileRaised((0,2) blur 8 #1A16190F)', (tester) async {
    await pump(tester, _summary());

    for (final label in ['인스타그램', '이벤트']) {
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

  testWidgets('링크 칸 속 — 그림 원 40 → 6 → 라벨 12/600 ink lh1.4 세로 가운데 · 인스타 로고 28 · 선물 28', (tester) async {
    await pump(tester, _summary());

    final instagram = tileOf('인스타그램');
    final logo = find.descendant(of: instagram, matching: find.byType(Image));
    expect((tester.widget<Image>(logo).image as AssetImage).assetName, 'assets/images/brand-instagram-v1.webp');
    expect(tester.widget<Image>(logo).fit, BoxFit.contain);
    expect(tester.getSize(logo), const Size(28, 28));
    expect(tester.getCenter(logo), tester.getCenter(plateIn(instagram)));

    final event = tileOf('이벤트');
    final gift = tester.widget<Icon3d>(find.descendant(of: event, matching: find.byType(Icon3d)));
    expect((gift.icon, gift.size), (AppIcon3d.gift, 28.0));
    expect(tester.getCenter(find.byWidget(gift)), tester.getCenter(plateIn(event)));

    for (final label in ['인스타그램', '이벤트']) {
      final tile = tileOf(label);
      final plate = tester.getRect(plateIn(tile));
      final text = tester.getRect(find.text(label));
      // 세로 가운데 — 원 위 여백 == 라벨 아래 여백
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
    await pump(tester, _summary());

    for (final label in ['인스타그램', '이벤트']) {
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
      expect(tester.getCenter(arrow), rect.center, reason: label);
    }
  });

  testWidgets('곧 열려요 칸 `BoTMl` — canvas · hairlineSoft 1 테두리 · 바깥 그림자 없음 · 안쪽 그림자(inner (0,1) blur 4 #0000000F)를 모서리 안에 그린다', (tester) async {
    await pump(tester, _summary());

    final cell = soonTile();
    final container = tester.widget<Container>(cell);
    final face = container.decoration! as BoxDecoration;
    expect(face.color, AppColors.canvas);
    expect(face.borderRadius, BorderRadius.circular(14));
    expect(face.boxShadow, isNull);
    // 테두리는 그림자 위에 그린다(채움 → 안쪽 그림자 → 테두리) — 안쪽 그림자가 칸 전체(104×80) 기준이 되게.
    final stroke = container.foregroundDecoration! as BoxDecoration;
    expect(stroke.border, Border.all(color: AppColors.hairlineSoft));
    expect(stroke.borderRadius, BorderRadius.circular(14));
    expect(
      cell,
      paints
        ..clipRRect(rrect: RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 104, 80), const Radius.circular(14)))
        ..path(color: AppElevation.homeTileInset.color)
        ..drrect(color: AppColors.hairlineSoft),
    );
  });

  testWidgets('곧 열려요 칸 속 — 그림 원 40 안 hourglass 20 muted → 6 → "곧 열려요" 12/600 muted, 세로 가운데', (tester) async {
    await pump(tester, _summary());

    final cell = soonTile();
    final plate = plateIn(cell);
    final glass = find.descendant(of: plate, matching: find.byIcon(AppIcons.hourglass));
    expect((tester.widget<Icon>(glass).size, tester.widget<Icon>(glass).color), (20.0, AppColors.muted));
    expect(tester.getCenter(glass), tester.getCenter(plate));
    final plateRect = tester.getRect(plate);
    final label = tester.getRect(find.text('곧 열려요'));
    expect(plateRect.center.dx, tester.getCenter(cell).dx);
    expect(label.top, closeTo(plateRect.bottom + 6, 0.01));
    // 링크 칸과 같은 짜임(원 40 → 6 → 라벨 lh1.4)이라 한 줄의 원 · 라벨 높이가 나란하다.
    expect(plateRect.top - tester.getRect(cell).top, closeTo(tester.getRect(cell).bottom - label.bottom, 0.01));
    expect(plateRect.top, tester.getRect(plateIn(tileOf('인스타그램'))).top);
    expect(
      tester.widget<Text>(find.text('곧 열려요')).style,
      AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 1.4, color: AppColors.muted),
    );
  });

  testWidgets('곧 열려요 칸은 눌러도 반응이 없다 — 누름 칸 · 잉크 · 제스처 없음', (tester) async {
    await pump(tester, _summary());

    await tester.tap(find.text('곧 열려요'), warnIfMissed: false);
    await tester.pump();

    expect((instagramTaps, eventTaps), (0, 0));
    for (final type in [InkWell, GestureDetector]) {
      expect(find.descendant(of: soonTile(), matching: find.byType(type)), findsNothing, reason: '$type');
      expect(find.ancestor(of: find.text('곧 열려요'), matching: find.byType(type)), findsNothing, reason: '$type');
    }
  });

  testWidgets('인스타 · 이벤트 칸은 칸 전체(모서리 끝까지)가 눌리고 각자 부른다 — 통계 칸은 누르지 않는다', (tester) async {
    await pump(tester, _summary());

    await tester.tapAt(tester.getBottomRight(tileOf('인스타그램')) - const Offset(6, 6));
    await tester.tapAt(tester.getTopLeft(tileOf('이벤트')) + const Offset(6, 6));
    await tester.tap(find.text('가입 수'), warnIfMissed: false);
    await tester.pump();

    expect((instagramTaps, eventTaps), (1, 1));
    expect(find.ancestor(of: find.text('가입 수'), matching: find.byType(InkWell)), findsNothing);
  });

  testWidgets('눌림 잉크는 칸 자기 Material 에 그린다(COMMON 4-2) · 누름 칸 104×80(≥44)', (tester) async {
    await pump(tester, _summary());

    for (final label in ['인스타그램', '이벤트']) {
      final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      final painter = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(painter), tester.getSize(ink), reason: label);
      expect(tester.getSize(ink), const Size(104, 80), reason: label);
    }
  });

  testWidgets('낭독기 — 링크 칸은 버튼, 곧 열려요는 "곧 열려요(준비 중)"(버튼 아님), 통계는 숫자와 라벨', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, _summary());

    final instagram = tester.getSemantics(find.text('인스타그램')).getSemanticsData();
    expect(instagram.label, 'CampusMate 인스타그램 열기');
    expect(instagram.flagsCollection.isButton, isTrue);
    expect(instagram.hasAction(SemanticsAction.tap), isTrue);
    final event = tester.getSemantics(find.text('이벤트')).getSemanticsData();
    expect(event.label, '이벤트 보기');
    expect(event.flagsCollection.isButton, isTrue);
    final soon = tester.getSemantics(find.text('곧 열려요')).getSemanticsData();
    expect(soon.label, '곧 열려요(준비 중)');
    expect(soon.flagsCollection.isButton, isFalse);
    expect(soon.hasAction(SemanticsAction.tap), isFalse);
    expect(tester.getSemantics(find.text('가입 수')).getSemanticsData().flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  for (final scale in [1.5, 2.0]) {
    testWidgets('글자 $scale 배 — 넘치지 않고, 숫자 · 라벨이 칸에 잘리지 않으며 칸이 늘어난다', (tester) async {
      await pump(tester, _summary(), textScale: scale);

      expect(tester.takeException(), isNull);
      // 넘침 오류는 Flex 만 낸다 — 높이에 갇힌 글자는 오류 없이 잘리므로 글 상자마다 따로 본다.
      final clipped = [
        for (final element in find.descendant(of: find.byType(HomeGrid), matching: find.byType(RichText)).evaluate())
          if (element.renderObject case final RenderParagraph p
              when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                  p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
            p.text.toPlainText(),
      ];
      expect(clipped, isEmpty);
      for (final text in ['1,234,567', '전달된 카드', '인스타그램', '이벤트', '곧 열려요']) {
        final owner = text == '1,234,567' || text == '전달된 카드'
            ? statTileOf('전달된 카드')
            : (text == '곧 열려요' ? soonTile() : tileOf(text));
        final ownerRect = tester.getRect(owner);
        final textRect = tester.getRect(find.text(text));
        expect(ownerRect.contains(textRect.topLeft) && ownerRect.contains(textRect.bottomRight - const Offset(0.01, 0.01)), isTrue,
            reason: '$text 가 칸 안에 있다');
      }
      expect(tester.getSize(find.byType(StatTile).first).height, greaterThanOrEqualTo(112));
      expect(tester.getSize(tileOf('인스타그램')).height, greaterThanOrEqualTo(80));
    });
  }
}
