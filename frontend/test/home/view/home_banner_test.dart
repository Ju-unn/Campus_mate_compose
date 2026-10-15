import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/home/view/home_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// 홈 배너(pen `HomeBanner`, 대장 전달 값): 328×84 · 모서리 16 · 좌우 14 · surfaceSoft,
/// 왼쪽 흰 원 44 + 아이콘 22 primary-text, 제목 15/700 #222 · 보조 12/600 #6A6A6A, 오른쪽 chevron-right 20 primary-text.
void main() {
  late int taps;

  Future<void> pump(WidgetTester tester) async {
    taps = 0;
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              HomeBanner(
                icon: AppIcons.camera,
                title: '제목',
                subtitle: '보조 글',
                semanticLabel: '배너 열기',
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Finder banner() => find.byType(HomeBanner);

  testWidgets('328×84 · 모서리 16 · surfaceSoft', (tester) async {
    await pump(tester);

    expect(tester.getSize(banner()), const Size(328, 84));
    final material = tester.widget<Material>(find.descendant(of: banner(), matching: find.byType(Material)).first);
    expect(material.color, AppColors.surfaceSoft);
    expect(material.borderRadius, BorderRadius.circular(16));
  });

  testWidgets('왼쪽 흰 원 44(좌 14) + 아이콘 22 primary-text, 오른쪽 chevron 20 primary-text(우 14)', (tester) async {
    await pump(tester);

    final origin = tester.getTopLeft(banner());
    final circle = find.ancestor(of: find.byIcon(AppIcons.camera), matching: find.byType(Container)).first;
    expect(tester.getRect(circle).shift(-origin), const Rect.fromLTWH(14, 20, 44, 44));
    final decoration = tester.widget<Container>(circle).decoration! as BoxDecoration;
    expect((decoration.color, decoration.shape), (AppColors.canvas, BoxShape.circle));
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.camera));
    expect((icon.size, icon.color), (22, AppColors.primaryText));
    final chevron = tester.widget<Icon>(find.byIcon(AppIcons.chevronRight));
    expect((chevron.size, chevron.color), (20, AppColors.primaryText));
    expect(tester.getTopRight(banner()).dx - tester.getTopRight(find.byIcon(AppIcons.chevronRight)).dx, 14);
  });

  testWidgets('제목 15/700 ink · 보조 12/600 muted', (tester) async {
    await pump(tester);

    final title = tester.widget<Text>(find.text('제목')).style!;
    expect((title.fontSize, title.fontWeight, title.color), (15, FontWeight.w700, AppColors.ink));
    final subtitle = tester.widget<Text>(find.text('보조 글')).style!;
    expect((subtitle.fontSize, subtitle.fontWeight, subtitle.color), (12, FontWeight.w600, AppColors.muted));
  });

  // 대장 검토 10-15(pen 제목 상자 20 · 제목 ↔ 보조 3).
  testWidgets('제목 줄 상자 20 · 제목 ↔ 보조 3', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.text('제목')).height, 20);
    expect(tester.getTopLeft(find.text('보조 글')).dy - tester.getBottomLeft(find.text('제목')).dy, 3);
  });

  testWidgets('배너 어디를 눌러도 한 번 — 왼쪽 끝 · 가운데 글 · 오른쪽 끝', (tester) async {
    await pump(tester);
    final rect = tester.getRect(banner());

    // 모서리 16 바깥(둥근 귀퉁이)은 칸이 아니다 — 가장자리는 세로 가운데에서 누른다.
    await tester.tapAt(Offset(rect.left + 2, rect.center.dy));
    await tester.tap(find.text('보조 글'));
    await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
    await tester.pumpAndSettle();

    expect(taps, 3);
  });

  testWidgets('눌림 잉크는 화면이 아니라 배너 칸 위에 그린다(COMMON 4-2)', (tester) async {
    await pump(tester);

    final ink = find.descendant(of: banner(), matching: find.byType(InkWell));
    final painter = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.getSize(painter), tester.getSize(ink));
  });

  testWidgets('낭독기는 배너 하나를 "배너 열기" 버튼으로 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final data = tester.getSemantics(banner()).getSemanticsData();
    expect(data.label, '배너 열기');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}
