import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/received_reviews_screen.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../safety/model/fake_safety_repository.dart';
import '../model/fake_friend_review_repository.dart';

const _notice = '받은 리뷰는 직접 삭제할 수 없어요. 부적절한 내용은 신고해주세요.';

/// 20c 받은 리뷰(pen `HWM2G`, 값표 B §2). 신고는 카드 깃발 → 기존 신고 시트, 차단은 하지 않는다(P1).
void main() {
  late FakeFriendReviewRepository reviews;
  late FakeSafetyRepository safety;

  setUp(() {
    reviews = FakeFriendReviewRepository()
      ..received = Success([
        friendReviewFixture(id: 'r1', nickname: '달빛', comment: '처음엔 조용해 보여도 친해지면 세심해요.'),
        friendReviewFixture(id: 'r2', nickname: '봄바람', tags: const ['배려가 깊어요', '유머 감각이 좋아요']),
      ]);
    safety = FakeSafetyRepository();
  });

  /// `/me`(15) 위에 push 로 연다 — [pushed] 가 false 면 푸시 알림처럼 `go` 로 바로 연다(스택 한 장).
  Future<GoRouter> pump(WidgetTester tester, {bool pushed = true, double scale = 1, bool settle = true}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [
      friendReviewRepositoryProvider.overrideWithValue(reviews),
      safetyRepositoryProvider.overrideWithValue(safety),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: pushed ? AppRoutes.myProfile : AppRoutes.friendReviews,
      routes: [
        GoRoute(path: AppRoutes.myProfile, builder: (context, state) => const Scaffold(body: Text('내 프로필'))),
        GoRoute(path: AppRoutes.friendReviews, builder: (context, state) => const ReceivedReviewsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    if (pushed) unawaited(router.push(AppRoutes.friendReviews));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
    return router;
  }

  Finder backButton() => find.ancestor(of: find.byIcon(AppIcons.arrowLeft), matching: find.byType(IconButton));

  Rect noticeBox(WidgetTester tester) =>
      tester.getRect(find.ancestor(of: find.text(_notice), matching: find.byType(Container)).first);

  Future<void> report(WidgetTester tester, {String nickname = '달빛'}) async {
    final card = find.ancestor(of: find.text(nickname), matching: find.byType(FriendReviewCard));
    await tester.tap(find.descendant(of: card, matching: find.byIcon(AppIcons.flag)));
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsOneWidget);
    await tester.tap(find.text('광고·스팸'));
    await tester.pump();
    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();
  }

  group('틀(pen HWM2G)', () {
    testWidgets('앱바 56 — 뒤로 48(arrow-left 22 ink) + "받은 리뷰" 20/700 x60, 하단 내비 없음', (tester) async {
      await pump(tester);

      final bar = tester.getRect(find.byType(AppBar));
      expect(bar.height, 56);
      // 앱바 칸 높이(56)만큼 늘어나 누르는 영역은 48 이상, 가운데는 pen 과 같다.
      final back = tester.getRect(backButton());
      expect(back.width, 48);
      expect(back.height, greaterThanOrEqualTo(48));
      expect(back.center, Offset(32, bar.center.dy));
      final arrow = tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft));
      expect((arrow.size, arrow.color), (22, AppColors.ink));
      final title = find.text('받은 리뷰');
      expect(tester.getRect(title).left, 60);
      final style = tester.widget<Text>(title).style!;
      expect((style.fontSize, style.fontWeight, style.color), (20, FontWeight.w700, AppColors.ink));
      expect(find.byType(AppBottomNav), findsNothing);
    });

    testWidgets('본문 여백 [8,16,24,16] — 안내 상자(pen lybcp) surfaceSoft r14 여백 14, info 20 primaryText, 간격 10', (tester) async {
      await pump(tester);

      final box = noticeBox(tester);
      expect(box.top - tester.getRect(find.byType(AppBar)).bottom, 8);
      expect((box.left, box.width), (16, 328));
      final decoration =
          tester.widget<Container>(find.ancestor(of: find.text(_notice), matching: find.byType(Container)).first).decoration!
              as BoxDecoration;
      expect((decoration.color, decoration.borderRadius), (AppColors.surfaceSoft, BorderRadius.circular(14)));
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.info));
      expect((icon.size, icon.color), (20, AppColors.primaryText));
      final iconRect = tester.getRect(find.byIcon(AppIcons.info));
      expect(iconRect.left - box.left, 14);
      expect(iconRect.center.dy, closeTo(box.center.dy, 0.5));
      final text = tester.getRect(find.text(_notice));
      expect(text.left - iconRect.right, 10);
      expect(text.top - box.top, 14);
      expect(box.bottom - text.bottom, 14);
      final style = tester.widget<Text>(find.text(_notice)).style!;
      expect((style.fontSize, style.color, style.fontWeight), (14, AppColors.body, FontWeight.w400));
    });

    testWidgets('카드는 안내 상자 뒤 16, 카드 사이 16, 폭 328, 카드마다 깃발', (tester) async {
      await pump(tester);

      final cards = find.byType(FriendReviewCard);
      expect(cards, findsNWidgets(2));
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      expect(first.top - noticeBox(tester).bottom, 16);
      expect(second.top - first.bottom, 16);
      expect(first.width, 328);
      expect(find.byIcon(AppIcons.flag), findsNWidgets(2));
      expect(reviews.receivedCount, 1);
    });
  });

  group('신고(깃발 → 기존 신고 시트, 차단 없음)', () {
    testWidgets('신고하면 friend_review 로 보내고 "신고했어요. 운영팀이 확인할게요" — 화면 · 카드 그대로', (tester) async {
      await pump(tester);

      await report(tester);

      expect(safety.reports.single.target, {'target_type': 'friend_review', 'target_id': 'r1'});
      expect(find.widgetWithText(AppToast, '신고했어요. 운영팀이 확인할게요'), findsOneWidget);
      expect(find.textContaining('차단'), findsNothing);
      expect(safety.blocked, isEmpty);
      expect(find.byType(ReceivedReviewsScreen), findsOneWidget);
      expect(find.text('달빛'), findsOneWidget);
    });

    testWidgets('이미 신고했으면 시트가 준 서버 문구를 그대로 띄우고 화면에 남는다', (tester) async {
      safety.reportResult = const FailureResult(ServerRejectedFailure('이미 신고를 완료했어요'));
      await pump(tester);

      await report(tester, nickname: '봄바람');

      expect(safety.reports.single.target, {'target_type': 'friend_review', 'target_id': 'r2'});
      expect(find.widgetWithText(AppToast, '이미 신고를 완료했어요'), findsOneWidget);
      expect(find.text('봄바람'), findsOneWidget);
    });

    testWidgets('하루 상한이면 시트가 준 문구를 띄우고 화면에 남는다', (tester) async {
      safety.reportResult = const FailureResult(RateLimitedFailure());
      await pump(tester);

      await report(tester);

      expect(find.widgetWithText(AppToast, '오늘은 더 신고할 수 없어요'), findsOneWidget);
      expect(find.byType(ReceivedReviewsScreen), findsOneWidget);
    });

    testWidgets('그새 가려진 리뷰(404)면 시트가 닫히고 서버 문구를 띄운다', (tester) async {
      safety.reportResult = const FailureResult(ServerRejectedFailure('리뷰를 찾을 수 없어요'));
      await pump(tester);

      await report(tester);

      expect(find.byType(ReportSheet), findsNothing);
      expect(find.widgetWithText(AppToast, '리뷰를 찾을 수 없어요'), findsOneWidget);
      expect(find.byType(ReceivedReviewsScreen), findsOneWidget);
    });

    testWidgets('시트를 닫으면 아무것도 보내지 않는다', (tester) async {
      await pump(tester);

      await tester.tap(find.byIcon(AppIcons.flag).first);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();

      expect(safety.reports, isEmpty);
      expect(find.byType(AppToast), findsNothing);
    });
  });

  group('빈 상태 · 읽는 중 · 실패(pen 에 없음 — 안내 상자는 늘 보인다)', () {
    testWidgets('받은 리뷰가 없으면 마스코트 120 · "아직 받은 리뷰가 없어요"(16f 빈 상태 모양)', (tester) async {
      reviews.received = const Success([]);
      await pump(tester);

      expect(find.text(_notice), findsOneWidget);
      expect(find.byType(FriendReviewCard), findsNothing);
      final mascot = find.byWidgetPredicate(
          (widget) => widget is Image && (widget.image as AssetImage).assetName == 'assets/images/mascot-female.png');
      expect(tester.getSize(mascot), const Size(120, 120));
      final title = tester.getRect(find.text('아직 받은 리뷰가 없어요'));
      expect(title.top - tester.getRect(mascot).bottom, 24);
    });

    testWidgets('읽는 동안은 안내 상자와 도는 표시', (tester) async {
      reviews.holdReceived = Completer<void>();
      await pump(tester, settle: false);

      expect(find.text(_notice), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      reviews.holdReceived!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(FriendReviewCard), findsNWidgets(2));
    });

    testWidgets('읽기에 실패하면 문구와 "다시 시도" — 누르면 다시 읽는다', (tester) async {
      reviews.received = const FailureResult(NetworkFailure());
      await pump(tester);

      expect(find.text(_notice), findsOneWidget);
      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      reviews.received = Success([friendReviewFixture(nickname: '달빛')]);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(reviews.receivedCount, 2);
      expect(find.text('달빛'), findsOneWidget);
    });
  });

  group('뒤로', () {
    testWidgets('15 에서 push 로 열었으면 뒤로 누르면 15 로 돌아간다', (tester) async {
      await pump(tester);

      await tester.tap(backButton());
      await tester.pumpAndSettle();

      expect(find.text('내 프로필'), findsOneWidget);
    });

    testWidgets('푸시로 바로 열려 돌아갈 곳이 없으면 뒤로(화살표 · 시스템)가 15 로 간다', (tester) async {
      await pump(tester, pushed: false);
      expect(find.byType(ReceivedReviewsScreen), findsOneWidget);

      // false 면 안드로이드가 뒤로가기를 "앱 종료" 로 처리한다(백로그 23).
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('내 프로필'), findsOneWidget);
    });
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다. 빈 상태도 같이 본다.
  for (final scale in [1.3, 2.0]) {
    for (final empty in [false, true]) {
      testWidgets('글자 배율 $scale${empty ? ' 빈 상태' : ''} 에서 넘치거나 잘리는 글자가 없다', (tester) async {
        if (empty) reviews.received = const Success([]);
        await pump(tester, scale: scale);

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
