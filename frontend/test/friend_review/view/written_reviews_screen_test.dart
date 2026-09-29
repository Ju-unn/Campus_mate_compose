import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/written_reviews_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_friend_review_repository.dart';

const _notice = '내가 남긴 리뷰는 언제든 지울 수 있어요.\n수정은 할 수 없어요.'; // pen DPIaV
const _emptyTitle = '아직 쓴 리뷰가 없어요'; // pen QlDBt/ZBzIg
const _emptyBody = '추천으로 연결된 친구에게\n리뷰를 남기면 여기에 모여요'; // pen QlDBt/DFs55
const _sheetTitle = '리뷰를 지울까요?'; // pen UClUE/xd8je
const _sheetBody = '지우면 봄바람님 프로필에서 바로 사라지고\n되돌릴 수 없어요.'; // pen UClUE/O7tR3q
const _deleted = '리뷰를 지웠어요'; // pen W7HENj/LGEZH

/// 20e 내가 쓴 리뷰(pen `FEysN`, 값표 20e §2~§5). 20c 사본 — 깃발 대신 휴지통, 지우면 카드가 빠진다.
void main() {
  late FakeFriendReviewRepository reviews;

  setUp(() {
    reviews = FakeFriendReviewRepository()
      ..written = Success([
        friendReviewFixture(id: 'r1', nickname: '달빛', comment: '처음엔 조용해 보여도 친해지면 세심해요.'),
        friendReviewFixture(id: 'r2', nickname: '봄바람', tags: const ['배려가 깊어요', '유머 감각이 좋아요']),
      ]);
  });

  /// `/me`(15) 위에 push 로 연다 — [pushed] 가 false 면 `go` 로 바로 연다(스택 한 장).
  Future<void> pump(WidgetTester tester, {bool pushed = true, double scale = 1, bool settle = true}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [friendReviewRepositoryProvider.overrideWithValue(reviews)]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: pushed ? AppRoutes.myProfile : AppRoutes.friendReviewsWritten,
      routes: [
        GoRoute(path: AppRoutes.myProfile, builder: (context, state) => const Scaffold(body: Text('내 프로필'))),
        GoRoute(path: AppRoutes.friendReviewsWritten, builder: (context, state) => const WrittenReviewsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    if (pushed) unawaited(router.push(AppRoutes.friendReviewsWritten));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Finder backButton() => find.ancestor(of: find.byIcon(AppIcons.arrowLeft), matching: find.byType(IconButton));

  Rect noticeBox(WidgetTester tester) =>
      tester.getRect(find.ancestor(of: find.text(_notice), matching: find.byType(Container)).first);

  Finder trashOf(String nickname) => find.descendant(
        of: find.ancestor(of: find.text(nickname), matching: find.byType(FriendReviewCard)),
        matching: find.byIcon(AppIcons.trash2),
      );

  Finder deleteButton() => find.widgetWithText(AppButton, '지우기');

  Future<void> openSheet(WidgetTester tester, {String nickname = '봄바람'}) async {
    await tester.tap(trashOf(nickname));
    await tester.pumpAndSettle();
    expect(find.text(_sheetTitle), findsOneWidget);
  }

  group('틀(pen FEysN)', () {
    testWidgets('앱바 56 — 뒤로 48(arrow-left 22 ink) + "내가 쓴 리뷰" 20/700 x60, 하단 내비 없음', (tester) async {
      await pump(tester);

      final bar = tester.getRect(find.byType(AppBar));
      expect(bar.height, 56);
      final back = tester.getRect(backButton());
      expect(back.width, 48);
      expect(back.center, Offset(32, bar.center.dy));
      final title = find.text('내가 쓴 리뷰');
      expect(tester.getRect(title).left, 60);
      final style = tester.widget<Text>(title).style!;
      expect((style.fontSize, style.fontWeight, style.color), (20, FontWeight.w700, AppColors.ink));
      expect(find.byType(AppBottomNav), findsNothing);
    });

    testWidgets('본문 여백 [8,16,24,16] — 안내 상자(pen lEVoU) 문구 두 줄 14 body, info 20 primaryText', (tester) async {
      await pump(tester);

      final box = noticeBox(tester);
      expect(box.top - tester.getRect(find.byType(AppBar)).bottom, 8);
      expect((box.left, box.width), (16, 328));
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.info));
      expect((icon.size, icon.color), (20, AppColors.primaryText));
      final style = tester.widget<Text>(find.text(_notice)).style!;
      expect((style.fontSize, style.color, style.fontWeight), (14, AppColors.body, FontWeight.w400));
    });

    testWidgets('카드(pen v6BbW · kwBwj)는 안내 뒤 16, 사이 16, 폭 328 — 머리는 받은 사람, 휴지통만 있고 깃발은 없다', (tester) async {
      await pump(tester);

      final cards = find.byType(FriendReviewCard);
      expect(cards, findsNWidgets(2));
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      expect(first.top - noticeBox(tester).bottom, 16);
      expect(second.top - first.bottom, 16);
      expect(first.width, 328);
      expect(find.descendant(of: cards.at(0), matching: find.text('달빛')), findsOneWidget);
      expect(find.text(friendReviewRelationLabel), findsNWidgets(2));
      expect(find.byIcon(AppIcons.trash2), findsNWidgets(2));
      expect(find.byIcon(AppIcons.flag), findsNothing);
      expect(reviews.writtenCount, 1);
    });
  });

  group('빈 상태(20e-1) · 읽는 중 · 실패', () {
    testWidgets('쓴 리뷰가 없으면 Empty(pen QlDBt) — 마스코트 120 → 24 → 제목 17/600 → 8 → 설명 14 muted 1.55, 가운데, 버튼 없음', (tester) async {
      reviews.written = const Success([]);
      await pump(tester);

      expect(find.text(_notice), findsOneWidget);
      expect(find.byType(FriendReviewCard), findsNothing);
      // pen J2kzx(Empty 마스터 마스코트) = 파란 목도리.
      final mascot = find.byWidgetPredicate(
          (widget) => widget is Image && (widget.image as AssetImage).assetName == 'assets/images/mascot-male.png');
      final mascotRect = tester.getRect(mascot);
      expect(mascotRect.size, const Size(120, 120));
      expect(mascotRect.center.dx, 180);
      final title = tester.getRect(find.text(_emptyTitle));
      final body = tester.getRect(find.text(_emptyBody));
      expect(title.top - mascotRect.bottom, 24);
      expect(title.height, 25);
      expect(body.top - title.bottom, 8);
      expect((title.center.dx, body.center.dx), (180, 180));
      // pen K2HbU 간격 16 뒤 빈 칸이 아래 여백 24 까지 채우고, 내용은 그 가운데.
      final regionTop = noticeBox(tester).bottom + 16;
      expect(mascotRect.top - regionTop, closeTo(780 - 24 - body.bottom, 0.5));
      final titleStyle = tester.widget<Text>(find.text(_emptyTitle)).style!;
      expect((titleStyle.fontSize, titleStyle.fontWeight, titleStyle.color), (17, FontWeight.w600, AppColors.ink));
      final bodyText = tester.widget<Text>(find.text(_emptyBody));
      expect((bodyText.style!.fontSize, bodyText.style!.color, bodyText.style!.height), (14, AppColors.muted, 1.55));
      expect((tester.widget<Text>(find.text(_emptyTitle)).textAlign, bodyText.textAlign), (TextAlign.center, TextAlign.center));
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('읽는 동안은 안내 상자와 도는 표시', (tester) async {
      reviews.holdWritten = Completer<void>();
      await pump(tester, settle: false);

      expect(find.text(_notice), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      reviews.holdWritten!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(FriendReviewCard), findsNWidgets(2));
    });

    testWidgets('읽기에 실패하면 문구와 "다시 시도" — 누르면 다시 읽는다', (tester) async {
      reviews.written = const FailureResult(NetworkFailure());
      await pump(tester);

      expect(find.text(_notice), findsOneWidget);
      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      reviews.written = Success([friendReviewFixture(nickname: '달빛')]);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(reviews.writtenCount, 2);
      expect(find.text('달빛'), findsOneWidget);
    });
  });

  group('지우기(20e-2 확인 → 20e-3 토스트)', () {
    testWidgets('휴지통 → AlertSheet(pen UClUE) — 제목 20/700 · 본문에 받은 사람 닉네임 14 muted 1.55 · 지우기 328×56 danger · 취소 48', (tester) async {
      await pump(tester);

      await openSheet(tester);

      final title = find.text(_sheetTitle);
      final titleStyle = tester.widget<Text>(title).style!;
      expect((titleStyle.fontSize, titleStyle.fontWeight, titleStyle.color), (20, FontWeight.w700, AppColors.ink));
      // pen xd8je 줄높이 속성 없음 · 렌더 29.
      expect(tester.getSize(title).height, 29);
      final bodyStyle = tester.widget<Text>(find.text(_sheetBody)).style!;
      expect((bodyStyle.fontSize, bodyStyle.color, bodyStyle.height), (14, AppColors.muted, 1.55));
      final delete = tester.widget<AppButton>(deleteButton());
      expect(delete.variant, AppButtonVariant.danger);
      final deleteRect = tester.getRect(deleteButton());
      expect(deleteRect.size, const Size(328, 56));
      final cancel = find.widgetWithText(AppButton, '취소');
      expect(tester.widget<AppButton>(cancel).variant, AppButtonVariant.text);
      final cancelRect = tester.getRect(cancel);
      expect(cancelRect.size, const Size(328, 48));
      // 세로: 손잡이 영역 28 → 8 → 제목 → 16 → 본문 → 16 → 지우기 → 8 → 취소 → 32, 시트는 화면 바닥에 붙는다.
      final titleRect = tester.getRect(title);
      final bodyRect = tester.getRect(find.text(_sheetBody));
      expect(bodyRect.top - titleRect.bottom, 16);
      expect(deleteRect.top - bodyRect.bottom, 16);
      expect(cancelRect.top - deleteRect.bottom, 8);
      expect(780 - cancelRect.bottom, 32);
      expect(titleRect.left, 16);
    });

    testWidgets('지우기 → 요청 한 번, 시트가 닫히고 카드가 빠지고 "리뷰를 지웠어요"(아이콘 없음, 가운데, 아래 24)', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(deleteButton());
      await tester.pumpAndSettle();

      expect(reviews.deletes, ['r2']);
      expect(find.text(_sheetTitle), findsNothing);
      expect(find.text('봄바람'), findsNothing);
      expect(find.text('달빛'), findsOneWidget);
      final toast = find.widgetWithText(AppToast, _deleted);
      expect(toast, findsOneWidget);
      expect(tester.widget<AppToast>(toast).leading, isNull);
      final rect = tester.getRect(toast);
      expect((rect.center.dx, rect.bottom, rect.height), (180, 780 - 24, 40));
    });

    testWidgets('지우는 중엔 버튼 안에 도는 표시 — 다시 눌러도, 시트를 닫고 다시 열어 눌러도 요청은 한 번', (tester) async {
      reviews.holdDelete = Completer<void>();
      await pump(tester);
      await openSheet(tester);

      await tester.tap(deleteButton());
      await tester.pump();
      expect(find.descendant(of: find.byType(AppButton).first, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      await tester.tap(find.byType(AppButton).first, warnIfMissed: false);
      await tester.pump();
      // 닫고(취소) 같은 카드를 다시 지워도 이미 가는 요청을 기다린다.
      await tester.tap(find.widgetWithText(AppButton, '취소'));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await tester.tap(deleteButton());
      await tester.pump();

      reviews.holdDelete!.complete();
      await tester.pumpAndSettle();
      expect(reviews.deletes, ['r2']);
      expect(find.text('봄바람'), findsNothing);
    });

    testWidgets('실패하면 시트를 닫고 서버 문구 토스트(circle-alert), 카드는 남는다', (tester) async {
      reviews.deleteResult = const FailureResult(NetworkFailure());
      await pump(tester);
      await openSheet(tester);

      await tester.tap(deleteButton());
      await tester.pumpAndSettle();

      expect(find.text(_sheetTitle), findsNothing);
      final toast = find.widgetWithText(AppToast, '네트워크 연결을 확인해 주세요');
      expect(toast, findsOneWidget);
      expect(find.descendant(of: toast, matching: find.byIcon(AppIcons.circleAlert)), findsOneWidget);
      expect(find.text('봄바람'), findsOneWidget);
    });

    testWidgets('그새 없어진 리뷰(404)면 서버 문구 토스트, 카드는 목록에서 빠진다', (tester) async {
      reviews.deleteResult = const FailureResult(ServerRejectedFailure('리뷰를 찾을 수 없어요'));
      await pump(tester);
      await openSheet(tester);

      await tester.tap(deleteButton());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppToast, '리뷰를 찾을 수 없어요'), findsOneWidget);
      expect(find.text('봄바람'), findsNothing);
      expect(reviews.writtenCount, 1);
    });

    testWidgets('취소하면 아무것도 보내지 않는다', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(find.widgetWithText(AppButton, '취소'));
      await tester.pumpAndSettle();

      expect(reviews.deletes, isEmpty);
      expect(find.byType(AppToast), findsNothing);
      expect(find.text('봄바람'), findsOneWidget);
    });

    // PR 3 검토 필수 1 — 닫히는 중(애니메이션 동안 State 는 살아 있다)에 응답이 오면 조건 없는 pop 이 밑 화면을 닫았다.
    testWidgets('지우는 중에 바깥을 눌러 닫고, 닫히는 사이 응답이 와도 20e 는 그대로다 — 결과 토스트는 뜬다', (tester) async {
      reviews.holdDelete = Completer<void>();
      await pump(tester);
      await openSheet(tester);
      await tester.tap(deleteButton());
      await tester.pump();

      await tester.tapAt(const Offset(180, 20));
      await tester.pump(const Duration(milliseconds: 50));
      reviews.holdDelete!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(WrittenReviewsScreen), findsOneWidget);
      expect(find.text('내 프로필'), findsNothing);
      expect(find.widgetWithText(AppToast, _deleted), findsOneWidget);
    });
  });

  group('뒤로', () {
    testWidgets('15 에서 push 로 열었으면 뒤로 누르면 15 로 돌아간다', (tester) async {
      await pump(tester);

      await tester.tap(backButton());
      await tester.pumpAndSettle();

      expect(find.text('내 프로필'), findsOneWidget);
    });

    testWidgets('돌아갈 곳이 없으면 뒤로(화살표 · 시스템)가 15 로 간다', (tester) async {
      await pump(tester, pushed: false);
      expect(find.byType(WrittenReviewsScreen), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('내 프로필'), findsOneWidget);
    });
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다. 빈 상태 · 확인 시트도 같이 본다.
  for (final scale in [1.3, 2.0]) {
    for (final view in ['목록', '빈 상태', '확인 시트']) {
      testWidgets('글자 배율 $scale $view 에서 넘치거나 잘리는 글자가 없다', (tester) async {
        if (view == '빈 상태') reviews.written = const Success([]);
        await pump(tester, scale: scale);
        if (view == '확인 시트') {
          await tester.ensureVisible(trashOf('봄바람'));
          await tester.pumpAndSettle();
          await openSheet(tester);
        }

        expect(tester.takeException(), isNull);
        final clipped = [
          for (final element in find.byType(RichText).evaluate())
            if (element.renderObject case final RenderParagraph p
                when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                    p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
              p.text.toPlainText(),
        ];
        expect(clipped, isEmpty);
      });
    }
  }
}
