import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/view/friend_code_screen.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:campus_mate/friend_review/view/my_friend_reviews_section.dart';
import 'package:campus_mate/friend_review/view/written_reviews_screen.dart';
import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_friend_review_repository.dart';

// pen 문구(20f eShpy · a6jyqI · Q3xfwm · uovMC · Mi3ux).
const _title = '친구 코드로 리뷰 쓰기'; // KXDke
const _guide = '친구에게 받은 추천 코드를 입력하면\n그 친구에게 리뷰를 남길 수 있어요'; // EuSqG
const _label = '친구 추천 코드'; // kZSO7/VCwQo
const _hint = '예: K7M2QX'; // kZSO7/p3T9Jb
const _notFound = '코드를 찾을 수 없어요. 다시 확인해 주세요.'; // BIJ3a/XATaU
const _already = '이미 리뷰를 남긴 친구예요'; // m9xLE/XATaU
const _tryLater = '잠시 후 다시 시도해 주세요.'; // mij9k/XATaU

/// 20f 친구 코드로 리뷰 쓰기(pen 360×780). 15 지인 리뷰 칸 "리뷰 쓰기" 줄에서 push 로 연다.
void main() {
  late FakeFriendReviewRepository reviews;

  setUp(() {
    reviews = FakeFriendReviewRepository();
  });

  /// 15(지인 리뷰 칸)를 밑에 깔고 20f 를 push 한다 — 남기면 15 가 쥔 "쓴 리뷰" 를 다시 읽는지 볼 수 있다.
  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [friendReviewRepositoryProvider.overrideWithValue(reviews)]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(
          path: AppRoutes.myProfile,
          builder: (context, state) => Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: const [MyFriendReviewsSection()]),
          ),
        ),
        GoRoute(path: AppRoutes.friendReviewCode, builder: (context, state) => const FriendCodeScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    unawaited(router.push(AppRoutes.friendReviewCode));
    await tester.pumpAndSettle();
  }

  Finder field() => find.byType(TextField);
  Finder button() => find.byType(AppButton);
  AppButton buttonWidget(WidgetTester tester) => tester.widget<AppButton>(button());
  OutlineInputBorder enabledBorder(WidgetTester tester) =>
      tester.widget<TextField>(field()).decoration!.enabledBorder! as OutlineInputBorder;

  Future<void> enterAndCheck(WidgetTester tester, String code) async {
    await tester.enterText(field(), code);
    await tester.pump();
    await tester.tap(button());
    await tester.pumpAndSettle();
  }

  void near(double actual, double expected) => expect(actual, moreOrLessEquals(expected, epsilon: 0.01));

  /// 입력칸 아래 한 줄(pen ErrorRow a1eaV): 아이콘 14 → 4 → 12/400 글자, 칸 아래 8, 바뀌면 낭독기가 바로 읽는다.
  void expectNote(WidgetTester tester, String text, IconData icon, Color color) {
    final note = find.text(text);
    final style = tester.widget<Text>(note).style!;
    expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, color));
    final iconFinder = find.byIcon(icon);
    final iconWidget = tester.widget<Icon>(iconFinder);
    expect((iconWidget.size, iconWidget.color), (14, color));
    near(tester.getRect(note).left - tester.getRect(iconFinder).right, 4);
    near(tester.getRect(iconFinder).left, tester.getRect(field()).left);
    near(tester.getRect(note).top - tester.getRect(field()).bottom, 8);
    near(tester.getRect(iconFinder).center.dy, tester.getRect(note).center.dy);
    expect(
      find.ancestor(of: note, matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true)),
      findsOneWidget,
    );
  }

  group('20f-1 입력 전(pen eShpy)', () {
    testWidgets('앱바 56 · 여백 좌 8 · 뒤로 48(arrow-left 22 ink) · 제목 20/700 ink x60', (tester) async {
      await pump(tester);

      expect(tester.getRect(find.byType(AppBar)).height, 56);
      final back = find.byTooltip(const DefaultMaterialLocalizations().backButtonTooltip);
      expect(tester.getRect(back), const Rect.fromLTWH(8, 4, 48, 48));
      final arrow = tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft));
      expect((arrow.size, arrow.color), (22, AppColors.ink));
      final title = find.text(_title);
      final style = tester.widget<Text>(title).style!;
      expect((style.fontSize, style.fontWeight, style.color, style.height), (20, FontWeight.w700, AppColors.ink, 1.5));
      expect(tester.getRect(title).left, 60);
    });

    testWidgets('본문 좌우 24 — 위 32 · 안내문 16/400 body 1.6 · 32 · 라벨 14/600 body 렌더 20 · 8 · 칸 312×52', (tester) async {
      await pump(tester);

      final guide = tester.getRect(find.text(_guide));
      expect((guide.left, guide.top, guide.width), (24, 56 + 32, 312));
      final guideStyle = tester.widget<Text>(find.text(_guide)).style!;
      expect((guideStyle.fontSize, guideStyle.fontWeight, guideStyle.color, guideStyle.height), (16, FontWeight.w400, AppColors.body, 1.6));
      final label = tester.getRect(find.text(_label));
      near(label.top - guide.bottom, 32);
      expect((label.left, label.height), (24, 20));
      final labelStyle = tester.widget<Text>(find.text(_label)).style!;
      expect((labelStyle.fontSize, labelStyle.fontWeight, labelStyle.color), (14, FontWeight.w600, AppColors.body));
      final box = tester.getRect(field());
      near(box.top - label.bottom, 8);
      expect((box.left, box.width, box.height), (24, 312, 52));
    });

    testWidgets('칸(PccKZ/TDM1r) 바탕 #F7F7F7 · 모서리 12 · 테두리 #DDDDDD 1, 자리표시 "예: K7M2QX" 16 muted 왼쪽 16', (tester) async {
      await pump(tester);

      final decoration = tester.widget<TextField>(field()).decoration!;
      expect((decoration.filled, decoration.fillColor), (true, AppColors.surfaceSoft));
      final border = enabledBorder(tester);
      expect((border.borderSide.color, border.borderSide.width, border.borderRadius), (AppColors.hairline, 1, BorderRadius.circular(12)));
      final hint = find.text(_hint);
      final hintStyle = tester.widget<Text>(hint).style!;
      expect((hintStyle.fontSize, hintStyle.color), (16, AppColors.muted));
      expect(tester.getRect(hint).left - tester.getRect(field()).left, 16);
      near(tester.getRect(hint).center.dy, tester.getRect(field()).center.dy);
    });

    testWidgets('버튼(HE8FZ) 하단 고정 312×52 · 아래 28 · "확인" — 비어 있으면 꺼짐(#E5E5E5 · #929292)', (tester) async {
      await pump(tester);

      expect(tester.getRect(button()), const Rect.fromLTWH(24, 780 - 28 - 52, 312, 52));
      expect((buttonWidget(tester).label, buttonWidget(tester).onPressed), ('확인', null));
      final material = tester.widget<Material>(find.descendant(of: button(), matching: find.byType(Material)).first);
      expect(material.color, AppColors.primaryDisabled);
      final labelStyle = tester.widget<Text>(find.text('확인')).style!;
      expect((labelStyle.fontSize, labelStyle.fontWeight), (16, FontWeight.w700));
      final rendered = tester.widget<RichText>(find.descendant(of: find.text('확인'), matching: find.byType(RichText)));
      expect(rendered.text.style!.color, AppColors.disabled);
    });

    testWidgets('코드를 넣으면 "확인" 이 켜진다(#FF385C · 흰 글자)', (tester) async {
      await pump(tester);

      await tester.enterText(field(), 'K7M2QX');
      await tester.pump();

      expect(buttonWidget(tester).onPressed, isNotNull);
      final material = tester.widget<Material>(find.descendant(of: button(), matching: find.byType(Material)).first);
      expect(material.color, AppColors.primary);
    });
  });

  group('입력', () {
    testWidgets('소문자 · 공백 · 기호는 대문자 영숫자로 — 붙여넣은 " k7 m-2qx " 도 K7M2QX', (tester) async {
      await pump(tester);

      await tester.enterText(field(), ' k7 m-2qx ');
      await tester.pump();

      expect(find.text('K7M2QX'), findsOneWidget);
    });

    testWidgets('공유 문구 전체(inviteShareText)를 붙여 넣으면 "추천 코드" 바로 뒤 토큰만 — CAMPUS 를 고르지 않는다', (tester) async {
      await pump(tester);

      await tester.enterText(field(), inviteShareText('K7M2QX'));
      await tester.pump();

      expect(find.text('K7M2QX'), findsOneWidget);
      expect(buttonWidget(tester).onPressed, isNotNull);
    });

    testWidgets('이미 친 글 뒤에 공유 문구를 붙여도, 소문자 코드여도 "추천 코드" 뒤 토큰 — 친 글은 버린다', (tester) async {
      await pump(tester);

      await tester.enterText(field(), 'AB${inviteShareText('k7m2qx')}');
      await tester.pump();

      expect(find.text('K7M2QX'), findsOneWidget);
    });

    testWidgets('"추천 코드" 뒤에 토큰이 없으면 빈 칸 — 다른 영숫자(CampusMate)를 코드로 삼지 않는다', (tester) async {
      await pump(tester);

      await tester.enterText(field(), 'CampusMate 추천 코드 를 넣어 줘');
      await tester.pump();

      expect(find.text('CAMPUS'), findsNothing);
      expect(buttonWidget(tester).onPressed, isNull);
    });

    testWidgets('코드 길이(6)를 넘는 글은 자른다 — 서버 상한 20 보다 짧다', (tester) async {
      await pump(tester);

      await tester.enterText(field(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
      await tester.pump();

      expect(find.text('ABCDEF'), findsOneWidget);
    });

    testWidgets('6자가 아니면 "확인" 이 꺼져 있고 키보드 "완료" 도 확인하지 않는다', (tester) async {
      await pump(tester);
      await tester.enterText(field(), 'K7M2Q');
      await tester.pump();

      expect(buttonWidget(tester).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(reviews.lookups, isEmpty);
    });

    testWidgets('키보드 "완료" 를 누르면 확인한다', (tester) async {
      await pump(tester);
      await tester.enterText(field(), 'K7M2QX');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(reviews.lookups, ['K7M2QX']);
      expect(tester.widget<TextField>(field()).textInputAction, TextInputAction.done);
    });

    testWidgets('확인 중엔 버튼 안 도는 표시 · 누름 막힘(pen 에 없는 상태)', (tester) async {
      reviews.holdLookup = Completer<void>();
      await pump(tester);
      await tester.enterText(field(), 'K7M2QX');
      await tester.pump();

      await tester.tap(button());
      await tester.pump();

      expect(buttonWidget(tester).isLoading, isTrue);
      await tester.tap(button());
      reviews.holdLookup!.complete();
      await tester.pumpAndSettle();
      expect(reviews.lookups, ['K7M2QX']);
    });
  });

  group('20f-2 오류(pen a6jyqI)', () {
    testWidgets('404 — 테두리 #C13515 2 · circle-alert 14 + 12 error "코드를 찾을 수 없어요. 다시 확인해 주세요." · 버튼은 켜진 "확인"', (tester) async {
      reviews.lookupResult = const FailureResult(ServerRejectedFailure('코드를 찾을 수 없어요'));
      await pump(tester);

      await enterAndCheck(tester, 'ZZZZZZ');

      final border = enabledBorder(tester);
      expect((border.borderSide.color, border.borderSide.width), (AppColors.error, 2));
      expectNote(tester, _notFound, AppIcons.circleAlert, AppColors.error);
      expect((buttonWidget(tester).label, buttonWidget(tester).onPressed != null), ('확인', true));
    });

    testWidgets('코드를 고치면 오류 줄 · 빨간 테두리가 사라진다', (tester) async {
      reviews.lookupResult = const FailureResult(ServerRejectedFailure('코드를 찾을 수 없어요'));
      await pump(tester);
      await enterAndCheck(tester, 'ZZZZZZ');

      await tester.enterText(field(), 'ZZZZZ');
      await tester.pump();

      expect(find.text(_notFound), findsNothing);
      expect(enabledBorder(tester).borderSide.color, AppColors.hairline);
    });
  });

  group('20f-3 확인 성공(pen Q3xfwm)', () {
    testWidgets('칸 아래 20 에 친구 줄(gN7m3) 312×64 — 아바타 · "쓰기" 없음, 닉네임 15/600 렌더 22 · 2 · 학교 14 body', (tester) async {
      reviews.lookupResult = Success(friendCodeMatchFixture(nickname: '봄바람', university: '테스트대학교'));
      await pump(tester);

      await enterAndCheck(tester, 'K7M2QX');

      final row = find.byType(WritableFriendRow);
      final rowRect = tester.getRect(row);
      expect((rowRect.left, rowRect.width, rowRect.height), (24, 312, 64));
      near(rowRect.top - tester.getRect(field()).bottom, 20);
      expect(find.descendant(of: row, matching: find.byType(FriendReviewInitial)), findsNothing);
      expect(find.descendant(of: row, matching: find.text('쓰기')), findsNothing);
      final name = find.descendant(of: row, matching: find.text('봄바람'));
      expect(tester.getRect(name).left - rowRect.left, 12);
      expect(tester.getRect(name).height, 22);
      final nameStyle = tester.widget<Text>(name).style!;
      expect((nameStyle.fontSize, nameStyle.fontWeight, nameStyle.color), (15, FontWeight.w600, AppColors.ink));
      expect(tester.widget<SchoolLabel>(find.descendant(of: row, matching: find.byType(SchoolLabel))).university, '테스트대학교');
      final school = find.descendant(of: row, matching: find.text('테스트대학교'));
      expect(tester.getRect(school).top - tester.getRect(name).bottom, 2);
      final decoration = tester.widget<DecoratedBox>(find.descendant(of: row, matching: find.byType(DecoratedBox)).first).decoration
          as BoxDecoration;
      expect((decoration.color, decoration.borderRadius, decoration.border), (AppColors.canvas, BorderRadius.circular(12), Border.all(color: AppColors.hairlineSoft)));
      // 성공에는 칸 아래 줄이 없다.
      for (final icon in [AppIcons.circleAlert, AppIcons.info, AppIcons.clock]) {
        expect(find.byIcon(icon), findsNothing);
      }
      expect(enabledBorder(tester).borderSide.color, AppColors.hairline);
    });

    testWidgets('버튼은 켜진 "리뷰 쓰기" — 누르면 20b(NHcsP) 가 확인 결과 닉네임으로 뜬다', (tester) async {
      await pump(tester);
      await enterAndCheck(tester, 'K7M2QX');

      expect((buttonWidget(tester).label, buttonWidget(tester).onPressed != null), ('리뷰 쓰기', true));
      await tester.tap(button());
      await tester.pumpAndSettle();

      final sheet = find.byType(FriendReviewComposeSheet);
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('봄바람')), findsOneWidget);
      expect(reviews.targetRequests, isEmpty);
    });

    testWidgets('20b 에서 남기면 코드로 보내고 — 돌아와 이미 쓴 친구가 되고 15 의 "쓴 리뷰" 를 다시 읽는다', (tester) async {
      await pump(tester);
      await enterAndCheck(tester, 'K7M2QX');
      final writtenBefore = reviews.writtenCount;
      await tester.tap(button());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '성실해요'));
      await tester.pump();
      await tester.tap(find.byKey(friendReviewSubmitKey));
      await tester.pumpAndSettle();

      expect(reviews.codeCreates.single.friendCode, 'K7M2QX');
      expect(find.byType(FriendReviewComposeSheet), findsNothing);
      expect(find.text(_already), findsOneWidget);
      expect((buttonWidget(tester).label, buttonWidget(tester).onPressed), ('리뷰 쓰기', null));
      expect(reviews.writtenCount, writtenBefore + 1);
    });

    testWidgets('20b 저장이 409 면 시트 안 토스트 — 닫으면 다시 확인해 이미 쓴 친구(20f-3b)가 된다', (tester) async {
      reviews.createResult = const FailureResult(ServerRejectedFailure('이미 리뷰를 남겼어요'));
      await pump(tester);
      await enterAndCheck(tester, 'K7M2QX');
      await tester.tap(button());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '성실해요'));
      await tester.pump();
      await tester.tap(find.byKey(friendReviewSubmitKey));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(FriendReviewComposeSheet), matching: find.text('이미 리뷰를 남겼어요')), findsOneWidget);
      reviews.lookupResult = Success(friendCodeMatchFixture(alreadyReviewed: true));

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(FriendReviewComposeSheet), findsNothing);
      expect(find.text(_already), findsOneWidget);
      expect((buttonWidget(tester).label, buttonWidget(tester).onPressed), ('리뷰 쓰기', null));
      expect(reviews.lookups, ['K7M2QX', 'K7M2QX']);
    });

    testWidgets('20b 를 그냥 닫으면 그대로 — 다시 쓸 수 있다', (tester) async {
      await pump(tester);
      await enterAndCheck(tester, 'K7M2QX');
      await tester.tap(button());
      await tester.pumpAndSettle();

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(FriendReviewComposeSheet), findsNothing);
      expect(find.byType(FriendCodeScreen), findsOneWidget);
      expect(buttonWidget(tester).onPressed, isNotNull);
    });

    testWidgets('확인 뒤 코드를 고치면 친구 줄이 빠지고 버튼은 "확인"', (tester) async {
      await pump(tester);
      await enterAndCheck(tester, 'K7M2QX');

      await tester.enterText(field(), 'K7M2Q');
      await tester.pump();

      expect(find.byType(WritableFriendRow), findsNothing);
      expect(buttonWidget(tester).label, '확인');
    });
  });

  group('20f-3b 이미 쓴 친구(pen uovMC)', () {
    testWidgets('칸 아래 8 에 info 14 + 12 muted "이미 리뷰를 남긴 친구예요" · 테두리 기본 · 20 아래 친구 줄 · "리뷰 쓰기" 꺼짐', (tester) async {
      reviews.lookupResult = Success(friendCodeMatchFixture(alreadyReviewed: true));
      await pump(tester);

      await enterAndCheck(tester, 'K7M2QX');

      expectNote(tester, _already, AppIcons.info, AppColors.muted);
      expect(enabledBorder(tester).borderSide.color, AppColors.hairline);
      near(tester.getRect(find.byType(WritableFriendRow)).top - tester.getRect(find.text(_already)).bottom, 20);
      expect((buttonWidget(tester).label, buttonWidget(tester).onPressed), ('리뷰 쓰기', null));
    });
  });

  group('20f-4 횟수 제한(pen Mi3ux)', () {
    testWidgets('429 — 테두리 기본 · clock 14 + 12 error "잠시 후 다시 시도해 주세요." · "확인" 꺼짐', (tester) async {
      reviews.lookupResult = const FailureResult(RateLimitedFailure());
      await pump(tester);

      await enterAndCheck(tester, 'K7M2QX');

      expect(enabledBorder(tester).borderSide.color, AppColors.hairline);
      expectNote(tester, _tryLater, AppIcons.clock, AppColors.error);
      expect((buttonWidget(tester).label, buttonWidget(tester).onPressed), ('확인', null));
    });
  });

  testWidgets('그 밖의 실패(pen 에 없음)는 circle-alert + 문구, 테두리는 기본 · 다시 확인할 수 있다', (tester) async {
    reviews.lookupResult = const FailureResult(NetworkFailure());
    await pump(tester);

    await enterAndCheck(tester, 'K7M2QX');

    expectNote(tester, '네트워크 연결을 확인해 주세요', AppIcons.circleAlert, AppColors.error);
    expect(enabledBorder(tester).borderSide.color, AppColors.hairline);
    expect(buttonWidget(tester).onPressed, isNotNull);
  });

  testWidgets('키보드가 올라오면 버튼은 키보드 위 28 — 넘치지 않고 위 칸만 스크롤한다', (tester) async {
    reviews.lookupResult = Success(friendCodeMatchFixture(alreadyReviewed: true));
    await pump(tester);
    await enterAndCheck(tester, 'K7M2QX');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);

    await tester.showKeyboard(field());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getRect(button()).bottom, 780 - 300 - 28);
    expect(tester.getRect(find.byType(WritableFriendRow)).bottom, lessThanOrEqualTo(tester.getRect(button()).top));
  });

  testWidgets('뒤로 누르면 15 로 돌아간다', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip(const DefaultMaterialLocalizations().backButtonTooltip));
    await tester.pumpAndSettle();

    expect(find.byType(FriendCodeScreen), findsNothing);
    expect(find.byType(MyFriendReviewsSection), findsOneWidget);
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다. 글이 가장 많은 20f-3b 로 본다.
  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      reviews.lookupResult = Success(friendCodeMatchFixture(alreadyReviewed: true));
      await pump(tester, scale: scale);
      await enterAndCheck(tester, 'K7M2QX');

      expect(tester.takeException(), isNull);
      final screen = find.byType(FriendCodeScreen);
      // 자리표시는 폭 검사에서만 뺀다 — 테스트 글꼴은 라틴 글자도 1em 폭이라 2.0 에서 286 > 280 이 되지만,
      // Pretendard 로는 약 170 이라 칸(280) 안이다. 높이는 본다.
      final clipped = [
        for (final element in find.descendant(of: screen, matching: find.byType(RichText)).evaluate())
          if (element.renderObject case final RenderParagraph p
              when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                  (p.text.toPlainText() != _hint && p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
            p.text.toPlainText(),
      ];
      expect(clipped, isEmpty);
      // 칸 · 친구 줄은 최소 높이라 커진 글자를 따라 늘어난다.
      expect(tester.getSize(field()).height, greaterThanOrEqualTo(52));
      expect(tester.getSize(find.byType(WritableFriendRow)).height, greaterThanOrEqualTo(64));
    });
  }
}
