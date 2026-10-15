import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/home_grid.dart';
import 'package:campus_mate/home/view/stat_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

HomeSummary _summary({int delivered = 1234567, int signups = 862, int conversations = 391}) => HomeSummary(
      presentPeopleImages: const [],
      deliveredCards: delivered,
      signups: signups,
      conversationsStarted: conversations,
      reviewRating: 4.6,
      reviewCount: 57,
      campuses: const [],
      profileCompletionPercent: 40,
    );

/// pen 09b 6칸 그리드 `M5hpo7`(대장 전달 확정 값 10-15, 정정 — 감싸는 패널 없이 칸마다 primaryWash 한 색). 홈 본문 폭 328 안에 둔다.
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

  testWidgets('3열 × 2행 · 칸 104×96 · 간격 8 · 전체 328×200', (tester) async {
    await pump(tester, _summary());

    expect(tester.getSize(find.byType(HomeGrid)), const Size(328, 200));
    final first = tester.getRect(find.byType(StatTile).at(0));
    // 감싸는 패널 · 안쪽 여백이 없다(대장 10-15 정정) — 첫 칸이 그리드 왼쪽 위에서 바로 시작한다.
    expect(first.topLeft, tester.getTopLeft(find.byType(HomeGrid)));
    final second = tester.getRect(find.byType(StatTile).at(1));
    final instagram = tester.getRect(tileOf('인스타그램'));
    expect(first.size, const Size(104, 96));
    expect(second.left - first.right, 8);
    expect(instagram.top - first.bottom, 8);
    expect(instagram.size, const Size(104, 96));
    final placeholder = find.ancestor(of: find.text('곧 열려요'), matching: find.byType(Container)).first;
    expect(tester.getRect(placeholder).right, 16 + 328);
  });

  testWidgets('위 행 통계 `gyzyR` — 한 색 primaryWash · 테두리 없음 · 모서리 14 · 그림 칸 40 → 숫자 24/700 ink(33) → 라벨 12/600 muted(17), 세로 가운데', (tester) async {
    // 칸 폭에 드는 숫자로 본다 — 넓은 숫자는 줄을 바꾸지 않고 칸 안에서 줄어든다(아래 테스트).
    await pump(tester, _summary(delivered: 123));

    for (final (label, value, icon, scale) in [
      ('전달된 카드', '123', AppIcon3d.send, 1.25), // pen 값(대장 10-15 재검토) — 옛 `krua8` 과 같다
      ('가입 수', '862', AppIcon3d.join, 1.16),
      ('시작된 대화', '391', AppIcon3d.chat, 1.0),
    ]) {
      final tile = find.ancestor(of: find.text(label), matching: find.byType(StatTile));
      final box = tester.widget<Container>(find.descendant(of: tile, matching: find.byType(Container)).first).decoration!
          as BoxDecoration;
      expect((box.color, box.borderRadius, box.border), (AppColors.primaryWash, BorderRadius.circular(14), null), reason: label);
      final plate = tester.getRect(plateIn(tile));
      final number = tester.getRect(find.text(value));
      final caption = tester.getRect(find.text(label));
      expect(plate.size, const Size(40, 40), reason: label);
      expect(plate.top - tester.getRect(tile).top, 3, reason: label); // (96 − 90) / 2
      expect(number.top, plate.bottom, reason: label);
      expect(number.height, 33, reason: label);
      expect(caption.top, number.bottom, reason: label);
      expect(caption.height, 17, reason: label);
      final icon3d = tester.widget<Icon3d>(find.descendant(of: tile, matching: find.byType(Icon3d)));
      expect((icon3d.icon, icon3d.size), (icon, 30.0), reason: label);
      final transform = find.ancestor(of: find.byWidget(icon3d), matching: find.byType(Transform)).first;
      expect(tester.widget<Transform>(transform).transform.getMaxScaleOnAxis(), closeTo(scale, 0.001), reason: label);
      expect(tester.widget<Text>(find.text(value)).style!.fontSize, 24, reason: label);
      expect(tester.widget<Text>(find.text(value)).style!.fontWeight, FontWeight.w700, reason: label);
      expect(tester.widget<Text>(find.text(value)).style!.color, AppColors.ink, reason: label);
      expect(
        tester.widget<Text>(find.text(label)).style,
        AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 17 / 12, color: AppColors.muted),
        reason: label,
      );
    }
  });

  testWidgets('숫자는 천 단위 쉼표 · 칸보다 넓으면 줄을 바꾸지 않고 칸 안에서 줄인다', (tester) async {
    await pump(tester, _summary());

    final number = find.text('1,234,567');
    expect(number, findsOneWidget);
    final tile = tester.getRect(find.ancestor(of: number, matching: find.byType(StatTile)));
    expect(tester.getRect(number).width, lessThanOrEqualTo(tile.width - 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('그림 칸 5개 — 40 원 · 흰 채움 · 테두리 1 hairlineSoft(안쪽) · 그림자 없음', (tester) async {
    await pump(tester, _summary());


    expect(find.byType(IconPlate), findsNWidgets(5));
    for (final plate in tester.widgetList<IconPlate>(find.byType(IconPlate))) {
      final box = tester.widget<Container>(find.descendant(of: find.byWidget(plate), matching: find.byType(Container)).first)
          .decoration! as BoxDecoration;
      expect(box.color, AppColors.canvas);
      expect(box.shape, BoxShape.circle);
      expect(box.border, Border.all(color: AppColors.hairlineSoft));
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

  testWidgets('세 통계가 모두 0 이면 위 행만 빠지고 링크 행은 남는다', (tester) async {
    await pump(tester, _summary(delivered: 0, signups: 0, conversations: 0));

    expect(find.byType(StatTile), findsNothing);
    expect(tester.getSize(find.byType(HomeGrid)), const Size(328, 96));
    expect(find.text('인스타그램'), findsOneWidget);
    expect(find.text('이벤트'), findsOneWidget);
    expect(find.text('곧 열려요'), findsOneWidget);
  });

  testWidgets('인스타 칸 `cStz1` — primaryWash + hairline 1 안쪽 테두리 · 그림 칸 안 로고 28 contain · 6 · 라벨 12/600 ink lh1.4 · 오른쪽 위(82,8) 화살표 14 muted', (tester) async {
    await pump(tester, _summary());
    final tile = tileOf('인스타그램');
    final origin = tester.getTopLeft(tile);

    final logo = find.descendant(of: tile, matching: find.byType(Image));
    expect((tester.widget<Image>(logo).image as AssetImage).assetName, 'assets/images/brand-instagram-v1.webp');
    expect(tester.widget<Image>(logo).fit, BoxFit.contain);
    expect(tester.getSize(logo), const Size(28, 28));
    expect(tester.getCenter(logo), tester.getCenter(plateIn(tile)));
    final plate = tester.getRect(plateIn(tile));
    final label = tester.getRect(find.text('인스타그램'));
    expect(plate.top - origin.dy, closeTo((96 - 63) / 2, 0.01)); // 40 + 6 + 17 = 63 을 세로 가운데
    expect(plate.center.dx, tester.getCenter(tile).dx);
    expect(label.top, closeTo(plate.bottom + 6, 0.01));
    expect(
      tester.widget<Text>(find.text('인스타그램')).style,
      AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 1.4, color: AppColors.ink),
    );
    final arrow = find.descendant(of: tile, matching: find.byIcon(AppIcons.arrowUpRight));
    expect(tester.getTopLeft(arrow) - origin, const Offset(82, 8));
    expect((tester.widget<Icon>(arrow).size, tester.widget<Icon>(arrow).color), (14.0, AppColors.muted));
    final face = tester.widget<Material>(tile);
    expect(face.color, AppColors.primaryWash);
    expect(
      face.shape,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.hairline)),
    );
  });

  testWidgets('이벤트 칸 — primaryWash · 흰 그림 칸 안 3D 선물 36 · 같은 화살표', (tester) async {
    await pump(tester, _summary());
    final tile = tileOf('이벤트');

    final gift = tester.widget<Icon3d>(find.descendant(of: tile, matching: find.byType(Icon3d)));
    expect((gift.icon, gift.size), (AppIcon3d.gift, 36.0));
    expect(tester.getCenter(find.byWidget(gift)), tester.getCenter(plateIn(tile)));
    final arrow = find.descendant(of: tile, matching: find.byIcon(AppIcons.arrowUpRight));
    expect(tester.getTopLeft(arrow) - tester.getTopLeft(tile), const Offset(82, 8));
    expect(tester.widget<Material>(tile).color, AppColors.primaryWash);
    expect(
      tester.widget<Material>(tile).shape,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.hairline)),
    );
  });

  testWidgets('자리표시 칸 `UlVom` — 바탕 없음 · hairline 1 테두리 · "곧 열려요" 12/600 muted · 누르지 않음', (tester) async {
    await pump(tester, _summary());

    final cell = find.ancestor(of: find.text('곧 열려요'), matching: find.byType(Container)).first;
    final box = tester.widget<Container>(cell).decoration! as BoxDecoration;
    expect(box.color, isNull);
    expect(box.border, Border.all(color: AppColors.hairline));
    expect(box.borderRadius, BorderRadius.circular(14));
    expect(tester.getSize(cell), const Size(104, 96));
    expect(
      tester.widget<Text>(find.text('곧 열려요')).style,
      AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
    );
    expect(find.ancestor(of: find.text('곧 열려요'), matching: find.byType(InkWell)), findsNothing);
  });

  testWidgets('인스타 · 이벤트 칸은 칸 전체가 눌리고 각자 부른다 — 통계 칸은 누르지 않는다', (tester) async {
    await pump(tester, _summary());

    await tester.tapAt(tester.getBottomRight(tileOf('인스타그램')) - const Offset(6, 6));
    await tester.tap(find.text('이벤트'));
    await tester.tap(find.text('가입 수'), warnIfMissed: false);
    await tester.pump();

    expect((instagramTaps, eventTaps), (1, 1));
    expect(find.ancestor(of: find.text('가입 수'), matching: find.byType(InkWell)), findsNothing);
  });

  testWidgets('눌림 잉크는 칸 자기 Material 에 그린다(COMMON 4-2)', (tester) async {
    await pump(tester, _summary());

    for (final label in ['인스타그램', '이벤트']) {
      final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      final painter = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(painter), tester.getSize(ink), reason: label);
      expect(tester.getSize(ink), const Size(104, 96), reason: label);
    }
  });

  testWidgets('낭독기 — 링크 칸은 버튼, 자리표시는 "곧 열려요(준비 중)", 통계는 숫자와 라벨', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, _summary());

    final instagram = tester.getSemantics(find.text('인스타그램')).getSemanticsData();
    expect(instagram.label, 'CampusMate 인스타그램 열기');
    expect(instagram.flagsCollection.isButton, isTrue);
    expect(instagram.hasAction(SemanticsAction.tap), isTrue);
    final event = tester.getSemantics(find.text('이벤트')).getSemanticsData();
    expect(event.label, '이벤트 보기');
    expect(event.flagsCollection.isButton, isTrue);
    expect(tester.getSemantics(find.text('곧 열려요')).getSemanticsData().label, '곧 열려요(준비 중)');
    expect(tester.getSemantics(find.text('가입 수')).getSemanticsData().flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  testWidgets('글자 2배에서도 넘치지 않고 칸이 늘어난다', (tester) async {
    await pump(tester, _summary(), textScale: 2);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(StatTile).first).height, greaterThanOrEqualTo(96));
  });
}
