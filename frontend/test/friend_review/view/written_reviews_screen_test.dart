import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/model/friend_review_tags.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
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
const _sectionTitle = '리뷰를 기다리는 친구'; // pen qa34E
const _sectionBody = '추천 코드로 이어진 친구예요. 지웠거나 놓친 리뷰도 다시 쓸 수 있어요.'; // pen AJ2hf

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
    final container = ProviderContainer(
      overrides: [
        friendReviewRepositoryProvider.overrideWithValue(reviews),
        // 학교 줄(SchoolLabel)은 로고 없이 이름만 — 로고 자리 · 크기는 school_label_test 가 지킨다.
        universityLogosProvider.overrideWith((ref) => const {}),
      ],
    );
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

  group('리뷰를 기다리는 친구(20e-4 pen bDZnr, 결함 A3)', () {
    final haneul = reviewTargetFixture(profileId: 'p3', nickname: '하늘', university: '한빛대학교');
    final saebyeok = reviewTargetFixture(profileId: 'p4', nickname: '새벽');

    Finder section() => find.text(_sectionTitle);
    // 앱바 제목과 같은 글이라 본문 안에서만 찾는다.
    Finder subtitle() => find.descendant(of: find.byType(ListView), matching: find.text('내가 쓴 리뷰'));
    Finder rowOf(String nickname) => find.ancestor(of: find.text(nickname), matching: find.byType(WritableFriendRow));
    Finder writeOf(String nickname) =>
        find.ancestor(of: find.descendant(of: rowOf(nickname), matching: find.text('쓰기')), matching: find.byType(Material)).first;

    testWidgets('친구가 있으면 안내 → 16 → 섹션(J3d8g8: 제목 16/700 → 8 → 설명 13 muted 1.5 → 8 → 줄 사이 8) → 16 → 소제목 Q3eosx 16/700 → 16 → 카드', (tester) async {
      reviews.writable = Success([haneul, saebyeok]);
      await pump(tester);

      final title = tester.getRect(section());
      final body = tester.getRect(find.text(_sectionBody));
      final rows = find.byType(WritableFriendRow);
      expect(rows, findsNWidgets(2));
      final first = tester.getRect(rows.at(0));
      final second = tester.getRect(rows.at(1));
      expect((title.top - noticeBox(tester).bottom, title.left), (16, 16));
      expect(body.top - title.bottom, 8);
      expect(first.top - body.bottom, 8);
      expect(second.top - first.bottom, 8);
      expect((first.left, first.width), (16, 328));
      final sub = tester.getRect(subtitle());
      expect((sub.top - second.bottom, sub.left), (16, 16));
      expect(tester.getRect(find.byType(FriendReviewCard).first).top - sub.bottom, 16);
      for (final heading in [section(), subtitle()]) {
        final style = tester.widget<Text>(heading).style!;
        expect((style.fontSize, style.fontWeight, style.color), (16, FontWeight.w700, AppColors.ink));
      }
      final bodyStyle = tester.widget<Text>(find.text(_sectionBody)).style!;
      expect((bodyStyle.fontSize, bodyStyle.color, bodyStyle.height), (13, AppColors.muted, 1.5));
      expect(reviews.writableCount, 1);
    });

    testWidgets('줄(LJhYM) 64 · 흰 바탕 r12 · 테두리 #EBEBEB 1 — 좌우 12, 이니셜 40 → 12 → 닉네임 15/600 · 2 · 학교, 오른쪽 "쓰기" 36 · 좌우 14 · r10 · rausch · 14/600 흰 글자', (tester) async {
      reviews.writable = Success([haneul]);
      await pump(tester);

      final row = rowOf('하늘');
      final rowRect = tester.getRect(row);
      expect(rowRect.height, 64);
      final decoration = tester.widget<DecoratedBox>(find.descendant(of: row, matching: find.byType(DecoratedBox)).first).decoration
          as BoxDecoration;
      expect(decoration.color, AppColors.canvas);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      expect(decoration.border, Border.all(color: AppColors.hairlineSoft));
      final initial = tester.getRect(find.descendant(of: row, matching: find.byType(FriendReviewInitial)));
      expect(initial.size, const Size(40, 40));
      expect((initial.left - rowRect.left, initial.center.dy), (12, rowRect.center.dy));
      // HP0vI 원 #FFF0F2 · YAaTW 글자 17/600 #222222.
      final initialStyle = tester.widget<Text>(find.descendant(of: row, matching: find.text('하'))).style!;
      expect((initialStyle.fontSize, initialStyle.fontWeight, initialStyle.color), (17, FontWeight.w600, AppColors.ink));
      final name = find.descendant(of: row, matching: find.text('하늘'));
      expect(tester.getRect(name).left - initial.right, 12);
      final nameStyle = tester.widget<Text>(name).style!;
      expect((nameStyle.fontSize, nameStyle.fontWeight, nameStyle.color), (15, FontWeight.w600, AppColors.ink));
      // YQMGC = 학교 줄 위젯(로고 16 · 간격 4 는 위젯이 글자 14 에서 정한다).
      expect(tester.widget<SchoolLabel>(find.descendant(of: row, matching: find.byType(SchoolLabel))).university, '한빛대학교');
      final school = find.descendant(of: row, matching: find.text('한빛대학교'));
      expect(tester.getRect(school).top - tester.getRect(name).bottom, 2);
      // YQMGC/ZD9sX 14 / 보통 / #3F3F3F / 1.5.
      final schoolStyle = tester.widget<Text>(school).style!;
      expect(
        (schoolStyle.fontSize, schoolStyle.fontWeight, schoolStyle.color, schoolStyle.height),
        (14, FontWeight.w400, AppColors.body, 1.5),
      );
      final write = writeOf('하늘');
      final writeRect = tester.getRect(write);
      expect((writeRect.height, rowRect.right - writeRect.right, writeRect.center.dy), (36, 12, rowRect.center.dy));
      expect(tester.getRect(find.text('쓰기')).left - writeRect.left, 14);
      final material = tester.widget<Material>(write);
      expect((material.color, material.borderRadius), (AppColors.primary, BorderRadius.circular(10)));
      final label = tester.widget<Text>(find.text('쓰기')).style!;
      expect((label.fontSize, label.fontWeight, label.color), (14, FontWeight.w600, AppColors.onPrimary));
    });

    testWidgets('0명이면 섹션 · 소제목 없이 20e 그대로(안내 → 16 → 카드)', (tester) async {
      await pump(tester);

      expect(reviews.writableCount, 1);
      expect(section(), findsNothing);
      expect(find.text('내가 쓴 리뷰'), findsOneWidget); // 앱바 제목뿐
    });

    testWidgets('읽는 중이면 섹션을 숨기고 도는 표시도 없다 — 읽히면 나온다(대장 ②)', (tester) async {
      reviews
        ..writable = Success([haneul])
        ..holdWritable = Completer<void>();
      await pump(tester);

      expect(section(), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(FriendReviewCard), findsNWidgets(2));
      reviews.holdWritable!.complete();
      await tester.pumpAndSettle();
      expect(section(), findsOneWidget);
    });

    testWidgets('읽기에 실패하면 섹션을 숨기고 오류 문구도 없다(대장 ②)', (tester) async {
      reviews.writable = const FailureResult(NetworkFailure());
      await pump(tester);

      expect(section(), findsNothing);
      expect(find.text('네트워크 연결을 확인해 주세요'), findsNothing);
      expect(find.byType(FriendReviewCard), findsNWidgets(2));
    });

    testWidgets('친구는 있고 쓴 리뷰가 0개면 섹션 → 소제목 → 기존 빈 상태(대장 ①)', (tester) async {
      reviews
        ..written = const Success([])
        ..writable = Success([haneul]);
      await pump(tester);

      expect(section(), findsOneWidget);
      final sub = tester.getRect(subtitle());
      expect(sub.top, greaterThan(tester.getRect(rowOf('하늘')).bottom));
      expect(tester.getRect(find.text(_emptyTitle)).top, greaterThan(sub.bottom));
      expect(find.text(_emptyBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"쓰기" → 그 친구 20b, 남기면 두 목록을 다시 읽어 남긴 친구가 섹션에서 빠진다', (tester) async {
      reviews.writable = Success([haneul, saebyeok]);
      await pump(tester);

      await tester.tap(writeOf('하늘'));
      await tester.pumpAndSettle();
      expect(tester.widget<FriendReviewComposeSheet>(find.byType(FriendReviewComposeSheet)).revieweeId, 'p3');
      reviews.writable = Success([saebyeok]);
      final chip = find.text(friendReviewTags.first);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      await tester.tap(find.byKey(friendReviewSubmitKey));
      await tester.pumpAndSettle();

      expect(reviews.creates.single.revieweeId, 'p3');
      expect((reviews.writableCount, reviews.writtenCount), (2, 2));
      expect(rowOf('하늘'), findsNothing);
      expect(rowOf('새벽'), findsOneWidget);
    });

    testWidgets('20b 를 남기지 않고 닫으면 다시 읽지 않는다', (tester) async {
      reviews.writable = Success([haneul]);
      await pump(tester);

      await tester.tap(writeOf('하늘'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(FriendReviewComposeSheet))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(FriendReviewComposeSheet), findsNothing);
      expect((reviews.writableCount, reviews.writtenCount), (1, 1));
    });

    testWidgets('리뷰를 지우면 기다리는 친구를 다시 읽는다 — 지운 친구가 섹션에 다시 나온다', (tester) async {
      await pump(tester);
      reviews.writable = Success([reviewTargetFixture(profileId: 'p5', nickname: '봄바람')]);

      await openSheet(tester);
      await tester.tap(deleteButton());
      await tester.pumpAndSettle();

      expect(reviews.writableCount, 2);
      expect(rowOf('봄바람'), findsOneWidget);
    });
  });

  group('지우기(20e-2 확인 → 20e-3 토스트)', () {
    testWidgets('휴지통 → AlertSheet(pen UClUE) — 제목 20/700 · 본문에 받은 사람 닉네임 14 muted 1.55 · 지우기 328×52 danger(HE8FZ 2026-10-01 개편) · 취소 48', (tester) async {
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
      expect(deleteRect.size, const Size(328, 52));
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
      expect(reviews.writableCount, 1);
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
      // 카드가 빠졌으니 그 친구는 다시 쓸 수 있다 — 기다리는 친구를 다시 읽는다(검토 권고 1).
      expect(reviews.writableCount, 2);
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
    for (final view in ['목록', '빈 상태', '확인 시트', '기다리는 친구']) {
      testWidgets('글자 배율 $scale $view 에서 넘치거나 잘리는 글자가 없다', (tester) async {
        if (view == '빈 상태') reviews.written = const Success([]);
        if (view == '기다리는 친구') {
          reviews.writable = Success([reviewTargetFixture(profileId: 'p3', nickname: '하늘', university: '한빛대학교')]);
        }
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
