import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/partner_reviews_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_friend_review_repository.dart';

const _sheetNotice = '리뷰는 추천 코드로 연결된 지인만 남길 수 있어요. 부적절한 내용은 신고해주세요.';

List<FriendReview> _reviews(int count) => [
      for (var i = 0; i < count; i++)
        friendReviewFixture(id: 'r$i', nickname: '친구$i', comment: '같이 있으면 대화가 편해요.'),
    ];

/// 14c "지인 리뷰" 섹션(pen `t3hFo` = `HlGva`) · 14d 리뷰 전체 시트(pen `FXNL4`), 값표 B §4 · §5.
void main() {
  late FakeFriendReviewRepository repository;

  setUp(() => repository = FakeFriendReviewRepository()..about = Success(_reviews(3)));

  /// 14c 카드 안쪽 폭 288 에 섹션만 놓는다.
  Future<void> pump(WidgetTester tester, {double scale = 1, bool settle = true}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [friendReviewRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('위 칸'),
                PartnerReviewsSection(profileId: 'p2', nickname: '토끼'),
                Text('아래 칸'),
              ],
            ),
          ),
        ),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  Finder showAllInk() => find.descendant(of: find.byType(PartnerReviewsSection), matching: find.byType(InkWell));

  group('14c 섹션', () {
    void expectHidden(WidgetTester tester) {
      expect(find.text('지인 리뷰'), findsNothing);
      expect(tester.getRect(find.text('아래 칸')).top, tester.getRect(find.text('위 칸')).bottom);
    }

    testWidgets('0개면 자리를 차지하지 않는다(P6)', (tester) async {
      repository.about = const Success([]);
      await pump(tester);

      expectHidden(tester);
    });

    testWidgets('읽기에 실패하면 자리를 차지하지 않는다', (tester) async {
      repository.about = const FailureResult(NetworkFailure());
      await pump(tester);

      expectHidden(tester);
    });

    testWidgets('읽는 동안은 자리를 차지하지 않고, 다 읽으면 나타난다', (tester) async {
      repository.about = Success(_reviews(1));
      await pump(tester, settle: false);

      expectHidden(tester);
      await tester.pumpAndSettle();
      expect(find.byType(FriendReviewCard), findsOneWidget);
    });

    testWidgets('헤더 → 8 → 카드 → 8 → 카드 → 13, 카드 폭 288, 3개면 2장 + "3개 모두 보기"', (tester) async {
      await pump(tester);

      expect(repository.aboutRequests, ['p2']);
      final title = tester.getRect(find.text('지인 리뷰').first);
      expect(title.top, tester.getRect(find.text('위 칸')).bottom);
      expect(title.height, 20);
      final cards = find.byType(FriendReviewCard);
      expect(cards, findsNWidgets(2));
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      expect(first.top - title.bottom, 8);
      expect(first.width, 288);
      expect(second.top - first.bottom, 8);
      expect(tester.getRect(find.text('아래 칸')).top - second.bottom, 13);
      expect(find.text('친구2'), findsNothing);
      // 깃발은 20c 만(대장 Q2).
      expect(find.byIcon(AppIcons.flag), findsNothing);
    });

    testWidgets('헤더 글자(pen Bw7Rz · e1E2HG · l8Yq7) — 14/600 muted · 12/600 primaryText + chevron 14, 간격 2', (tester) async {
      await pump(tester);

      final title = tester.widget<Text>(find.text('지인 리뷰').first).style!;
      expect((title.fontSize, title.fontWeight, title.color), (14, FontWeight.w600, AppColors.muted));
      final link = tester.widget<Text>(find.text('3개 모두 보기').first).style!;
      expect((link.fontSize, link.fontWeight, link.color), (12, FontWeight.w600, AppColors.primaryText));
      expect(tester.getRect(find.text('3개 모두 보기').first).height, 17);
      final chevron = tester.widget<Icon>(find.byIcon(AppIcons.chevronRight).first);
      expect((chevron.size, chevron.color), (14, AppColors.primaryText));
      final chevronRect = tester.getRect(find.byIcon(AppIcons.chevronRight).first);
      expect(chevronRect.left - tester.getRect(find.text('3개 모두 보기').first).right, 2);
      // 오른쪽 끝(카드 오른쪽 끝과 같다).
      expect(chevronRect.right, tester.getRect(find.byType(FriendReviewCard).first).right);
    });

    for (final count in [1, 2]) {
      testWidgets('$count개면 카드 $count장 — "모두 보기" 없음(2개 이하는 다 보인다)', (tester) async {
        repository.about = Success(_reviews(count));
        await pump(tester);

        expect(find.byType(FriendReviewCard), findsNWidgets(count));
        expect(find.textContaining('모두 보기'), findsNothing);
        expect(find.byIcon(AppIcons.chevronRight), findsNothing);
        expect(showAllInk(), findsNothing);
        final last = tester.getRect(find.byType(FriendReviewCard).last);
        expect(tester.getRect(find.text('아래 칸')).top - last.bottom, 13);
      });
    }

    testWidgets('"모두 보기" 는 보이는 줄 그대로, 누르는 영역은 44 이상 · 글자를 덮고, 눌림 효과는 자기 Material 에', (tester) async {
      await pump(tester);

      final ink = tester.getRect(showAllInk());
      expect(ink.height, greaterThanOrEqualTo(44));
      expect(ink.width, greaterThanOrEqualTo(44));
      final link = tester.getRect(find.text('3개 모두 보기').first).expandToInclude(tester.getRect(find.byIcon(AppIcons.chevronRight).first));
      expect(ink.expandToInclude(link), ink);
      // 보이는 자리는 pen 그대로 — 카드 위치가 밀리지 않는다.
      expect(tester.getRect(find.byType(FriendReviewCard).first).top - tester.getRect(find.text('지인 리뷰').first).bottom, 8);
      final material = find.ancestor(of: showAllInk(), matching: find.byType(Material)).first;
      expect(tester.getSize(material), ink.size);
    });

    testWidgets('낭독은 "3개 모두 보기" 한 번 — 높이 재는 사본은 읽히지 않는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('3개 모두 보기'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('모두 보기.*지인 리뷰|지인 리뷰.*모두 보기')), findsNothing);
      semantics.dispose();
    });
  });

  group('14d 시트(pen FXNL4)', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(showAllInk());
      await tester.pumpAndSettle();
    }

    Finder sheet() => find.byType(PartnerReviewsSheet);

    testWidgets('"모두 보기" 를 누르면 시트가 열리고 다시 읽지 않는다', (tester) async {
      await pump(tester);

      await open(tester);

      expect(sheet(), findsOneWidget);
      expect(repository.aboutRequests, ['p2']);
    });

    testWidgets('제목 "친구들이 본 {닉}" 20/700 · "리뷰 N개" 14/400 muted, 카드 전부 · 끝 안내 상자, 닫기 버튼 없음', (tester) async {
      await pump(tester);
      await open(tester);

      final title = find.descendant(of: sheet(), matching: find.text('친구들이 본 토끼'));
      final titleStyle = tester.widget<Text>(title).style!;
      expect((titleStyle.fontSize, titleStyle.fontWeight, titleStyle.color), (20, FontWeight.w700, AppColors.ink));
      expect(tester.getRect(title).height, 29);
      final count = find.descendant(of: sheet(), matching: find.text('리뷰 3개'));
      final countStyle = tester.widget<Text>(count).style!;
      expect((countStyle.fontSize, countStyle.fontWeight, countStyle.color), (14, FontWeight.w400, AppColors.muted));
      final sheetRect = tester.getRect(sheet());
      expect(sheetRect.width, 360);
      expect(tester.getRect(title).left - sheetRect.left, 16);
      expect(sheetRect.right - tester.getRect(count).right, 16);
      // 손잡이 영역 28 + 여백 8 → 제목.
      expect(tester.getRect(title).top - sheetRect.top, 36);
      final cards = find.descendant(of: sheet(), matching: find.byType(FriendReviewCard));
      expect(cards, findsNWidgets(3));
      expect(tester.getRect(cards.first).top - tester.getRect(title).bottom, 12);
      expect(tester.getRect(cards.at(1)).top - tester.getRect(cards.first).bottom, 12);
      expect(tester.getRect(cards.first).width, 328);
      expect(find.descendant(of: sheet(), matching: find.byIcon(AppIcons.flag)), findsNothing);
      expect(find.descendant(of: sheet(), matching: find.byIcon(AppIcons.x)), findsNothing);
      await tester.scrollUntilVisible(find.text(_sheetNotice), 200,
          scrollable: find.descendant(of: sheet(), matching: find.byType(Scrollable)));
      expect(tester.getRect(find.text(_sheetNotice)).top, greaterThan(tester.getRect(cards.last).bottom));
      expect(find.descendant(of: sheet(), matching: find.byIcon(AppIcons.info)), findsOneWidget);
    });

    testWidgets('시트 — 위 모서리 24 · 손잡이 36×4 hairline r2 · 그림자 (0,-2) 16', (tester) async {
      await pump(tester);
      await open(tester);

      final box = tester.widget<Container>(find.descendant(of: sheet(), matching: find.byType(Container)).first);
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.canvas);
      expect(decoration.borderRadius, const BorderRadius.vertical(top: Radius.circular(24)));
      expect(decoration.boxShadow!.single.offset, const Offset(0, -2));
      expect(decoration.boxShadow!.single.blurRadius, 16);
      final handle = find.byKey(partnerReviewsSheetHandleKey);
      expect(tester.getSize(handle), const Size(36, 4));
      expect(tester.getRect(handle).top - tester.getRect(sheet()).top, 12);
      final handleDecoration = tester.widget<Container>(handle).decoration! as BoxDecoration;
      expect((handleDecoration.color, handleDecoration.borderRadius), (AppColors.hairline, BorderRadius.circular(2)));
    });

    testWidgets('리뷰가 10개여도 화면 90% 까지만 크고 넘치지 않는다(스크롤)', (tester) async {
      repository.about = Success(_reviews(10));
      await pump(tester);
      await tester.tap(showAllInk());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(sheet()).height, lessThanOrEqualTo(780 * 0.9));
      await tester.scrollUntilVisible(find.text(_sheetNotice), 300,
          scrollable: find.descendant(of: sheet(), matching: find.byType(Scrollable)));
      expect(find.text(_sheetNotice), findsOneWidget);
    });

    testWidgets('내용이 화면 90% 보다 작으면 내용만큼만 크다(hug) — 안내 상자 뒤 28 에 시트 바닥', (tester) async {
      // 한마디 없는 카드 3장이면 pen 750 보다 짧아 90%(702) 안에 들어온다.
      repository.about = Success([for (var i = 0; i < 3; i++) friendReviewFixture(id: 'r$i', nickname: '친구$i')]);
      await pump(tester);
      await open(tester);

      final sheetRect = tester.getRect(sheet());
      expect(sheetRect.height, lessThan(780 * 0.9));
      expect(sheetRect.bottom, 780);
      final notice = tester.getRect(find.ancestor(of: find.text(_sheetNotice), matching: find.byType(Container)).first);
      expect(sheetRect.bottom - notice.bottom, 28);
      expect(notice.top - tester.getRect(find.byType(FriendReviewCard).last).bottom, 12);
    });
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다.
  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 섹션 · 시트에 넘치거나 잘리는 글자가 없다', (tester) async {
      await pump(tester, scale: scale);

      List<String> clipped() => [
            for (final element in find.byType(RichText).evaluate())
              if (element.renderObject case final RenderParagraph p
                  when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                      p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
                p.text.toPlainText(),
          ];
      expect(tester.takeException(), isNull);
      expect(clipped(), isEmpty);
      // 누르는 영역은 커진 글자를 여전히 덮는다.
      final ink = tester.getRect(showAllInk());
      expect(ink.expandToInclude(tester.getRect(find.text('3개 모두 보기').first)), ink);

      await tester.tap(showAllInk());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(clipped(), isEmpty);
    });
  }
}
