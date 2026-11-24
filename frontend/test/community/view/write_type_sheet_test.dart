import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/view/write_type_sheet.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// pen WriteTypeSheet `ELuBm`(360×282) — 17 커뮤니티 · 글쓰기 고르기 `LSCrq`.
void main() {
  CommunityKind? picked;
  var closed = false;

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    picked = null;
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showWriteTypeSheet(context);
                closed = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('제목 "무엇을 올릴까요?" 20/700 lh1.5 ls-0.4 ink, 시트는 화면 바닥에 붙은 282', (tester) async {
    await openSheet(tester);
    final style = tester.widget<Text>(find.text('무엇을 올릴까요?')).style!;
    expect((style.fontSize, style.fontWeight, style.height, style.letterSpacing, style.color),
        (20, FontWeight.w700, 1.5, -0.4, AppColors.ink));
    final sheet = tester.getRect(find.byType(WriteTypeSheet));
    expect((sheet.width, sheet.bottom), (360, 780));
    expect(sheet.height, closeTo(282, 0.5));
  });

  testWidgets('줄 둘(328×76 · surface-soft · 모서리 md · 사이 16): 투표(3D 투표 48) · 게시물(3D 편집 36), chevron 20 muted', (tester) async {
    await openSheet(tester);
    final poll = tester.getRect(find.byKey(WriteTypeSheet.rowKey(CommunityKind.poll)));
    final post = tester.getRect(find.byKey(WriteTypeSheet.rowKey(CommunityKind.post)));
    expect((poll.width, poll.height, post.height), (328, 76, 76));
    expect(post.top - poll.bottom, 16);
    final fill = tester.widget<Material>(
      find.ancestor(of: find.byKey(WriteTypeSheet.rowKey(CommunityKind.poll)), matching: find.byType(Material)).first,
    );
    expect(fill.color, AppColors.surfaceSoft);
    expect((fill.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppRadius.md));
    expect(tester.getSize(find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.vote)), const Size(48, 48));
    expect(tester.getSize(find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.pencil)), const Size(36, 36));
    expect(
      find.byWidgetPredicate((w) => w is Icon && w.icon == AppIcons.chevronRight && w.size == 20 && w.color == AppColors.muted),
      findsNWidgets(2),
    );
    expect(find.text('두 가지 중에서 골라 받아요'), findsOneWidget);
    expect(find.text('자유롭게 글을 써요'), findsOneWidget);
  });

  testWidgets('게시물을 누르면 시트가 닫히며 게시물을 돌려준다', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('게시물'));
    await tester.pumpAndSettle();
    expect((closed, picked), (true, CommunityKind.post));
  });

  testWidgets('투표를 누르면 투표를 돌려준다', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('투표'));
    await tester.pumpAndSettle();
    expect(picked, CommunityKind.poll);
  });
}
