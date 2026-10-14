import 'dart:async';
import 'dart:io';

import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../model/fake_friend_review_repository.dart';

/// pen `S0MR2b` 마스터 본문(`kgCWd`) — 296 폭에서 두 줄.
const _comment = '처음엔 조용해 보여도 친해지면 누구보다 세심하게 챙겨주는 친구예요.';

/// 주소는 지어낸 값이다(로고 · 아바타 그림은 네트워크로 받지 않는다 — 아래 HttpClient 가 대신 답한다).
const _logoUrl = 'https://logo.test/snu.webp';
const _avatarUrl = 'https://avatar.test/moon.webp';

/// 그림 요청을 받기만 하고 답하지 않는 HttpClient — 그림이 "아직 오는 중"이라 자리만 잡는다.
class _PendingHttpClient extends Mock implements HttpClient {}

/// 그림 요청마다 연결 오류를 내는 HttpClient — 그림을 못 불러온 경우.
class _FailingHttpClient extends Mock implements HttpClient {}

HttpClient _pending() {
  final client = _PendingHttpClient();
  when(() => client.getUrl(any())).thenAnswer((_) => Completer<HttpClientRequest>().future);
  return client;
}

HttpClient _failing() {
  final client = _FailingHttpClient();
  when(() => client.getUrl(any())).thenAnswer((_) async => throw const SocketException('없음'));
  return client;
}

Finder _networkImage(String url) =>
    find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url);

/// 그림이 실제로 그려지는 상자. Image 위젯 크기는 frameBuilder 가 감싼 틀(36 칸 · 원)까지라 그림 크기는 이것으로 잰다.
Finder _picture(String url) => find.descendant(of: _networkImage(url), matching: find.byType(RawImage));

/// FriendReviewCard(pen `S0MR2b`, 값표 B §3). 폭은 부모가 준다(20c · 14d 328, 14c 288).
void main() {
  setUpAll(() => registerFallbackValue(Uri()));
  // 그림 캐시가 앞 테스트의 그림(오는 중 · 실패)을 쥐고 있지 않게 비운다. 앞 테스트가 중간에 깨져 디버그 훅을
  // 못 되돌렸어도 다음 테스트로 번지지 않게 여기서도 되돌린다.
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    debugNetworkImageHttpClientProvider = null;
  });

  /// [client] 를 주면 그림 요청을 그 HttpClient 가 받는다. 디버그 훅은 테스트 본문 끝에서 되돌린다
  /// (불변식 검사가 tearDown 보다 먼저다 — school_label_test 와 같다).
  Future<void> pump(
    WidgetTester tester,
    FriendReview review, {
    VoidCallback? onReport,
    VoidCallback? onDelete,
    double width = 328,
    double scale = 1,
    Map<String, String> logos = const {},
    HttpClient? client,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    if (client != null) debugNetworkImageHttpClientProvider = () => client;
    await tester.pumpWidget(ProviderScope(
      overrides: [universityLogosProvider.overrideWith((ref) => logos)],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: FriendReviewCard(review: review, onReport: onReport, onDelete: onDelete),
            ),
          ),
        ),
      ),
    ));
    // 로고 표(FutureProvider)가 값을 내고, 실패하는 그림 요청이 errorBuilder 까지 가게 한 번 더.
    await tester.pump();
    await tester.pump();
  }

  FriendReview pen({
    String? university = '서울대학교',
    String? comment = _comment,
    List<String>? tags,
    String? avatarUrl,
  }) =>
      friendReviewFixture(
        nickname: '달빛',
        avatarUrl: avatarUrl,
        university: university,
        tags: tags ?? const ['약속을 잘 지켜요', '대화가 편해요'],
        comment: comment,
      );

  Rect box(WidgetTester tester, String text) =>
      tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(Container)).first);

  testWidgets('학교 배지 · 이니셜 · 닉네임 · 관계 · 태그 · 한마디가 pen 자리에 있다(높이 179)', (tester) async {
    await pump(tester, pen());

    final card = tester.getRect(find.byType(FriendReviewCard));
    expect(card.size, const Size(328, 179));
    // 머리 줄 y16 · 48 — 배지 36 → 10 → 이니셜 36 → 10 → 이름 칸.
    final badge = box(tester, '서');
    expect(badge.size, const Size(36, 36));
    expect(badge.topLeft - card.topLeft, const Offset(16, 22));
    final initial = box(tester, '달');
    expect(initial.size, const Size(36, 36));
    expect(initial.left - badge.right, 10);
    final name = tester.getRect(find.text('달빛'));
    expect(name.left - initial.right, 10);
    expect(name.height, 24);
    final relation = tester.getRect(find.text(friendReviewRelationLabel));
    expect(relation.top - name.bottom, 1);
    expect(relation.height, 19);
    // 이름 칸 44 는 머리 줄 48 가운데.
    expect(name.top - card.top, 16 + 2);
    // 태그 줄 y76 · 31, 본문 y119 · 44.
    final chip = box(tester, '약속을 잘 지켜요');
    expect(chip.top - card.top, 76);
    expect(chip.height, 31);
    expect(chip.left - card.left, 16);
    expect(box(tester, '대화가 편해요').left - chip.right, 8);
    final body = tester.getRect(find.text(_comment));
    expect(body.top - card.top, 119);
    expect(body.height, 44);
    expect(body.width, 296);
  });

  testWidgets('색 · 글자 — 배지 surfaceInk r8 흰 12/700, 이니셜 primaryWash 원 14/700, 칩 primaryWash 12/600', (tester) async {
    await pump(tester, pen());

    final card = tester.widget<Container>(
        find.descendant(of: find.byType(FriendReviewCard), matching: find.byType(Container)).first);
    expect((card.decoration! as BoxDecoration).color, AppColors.canvas);
    expect((card.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(14));
    expect(((card.foregroundDecoration! as BoxDecoration).border! as Border).top.color, AppColors.hairline);
    expect((card.decoration! as BoxDecoration).boxShadow, isNull);

    BoxDecoration decorationOf(String text) => tester
        .widget<Container>(find.ancestor(of: find.text(text), matching: find.byType(Container)).first)
        .decoration! as BoxDecoration;
    expect(decorationOf('서').color, AppColors.surfaceInk);
    expect(decorationOf('서').borderRadius, BorderRadius.circular(8));
    // pen NUNSp 테두리 hairline 1 — 폴백 설명(context)은 채움만 #222222 로 바꾼다고 해 테두리는 그대로 둔다.
    final badgeBorder = (tester
            .widget<Container>(find.ancestor(of: find.text('서'), matching: find.byType(Container)).first)
            .foregroundDecoration! as BoxDecoration)
        .border! as Border;
    expect((badgeBorder.top.color, badgeBorder.top.width), (AppColors.hairline, 1));
    expect(decorationOf('달').color, AppColors.primaryWash);
    expect(decorationOf('달').shape, BoxShape.circle);
    expect(decorationOf('약속을 잘 지켜요').color, AppColors.primaryWash);

    TextStyle styleOf(String text) => tester.widget<Text>(find.text(text)).style!;
    expect((styleOf('서').color, styleOf('서').fontSize, styleOf('서').fontWeight), (AppColors.onInk, 12, FontWeight.w700));
    expect((styleOf('달').color, styleOf('달').fontSize, styleOf('달').fontWeight),
        (AppColors.primaryText, 14, FontWeight.w700));
    expect((styleOf('달빛').color, styleOf('달빛').fontSize, styleOf('달빛').fontWeight), (AppColors.ink, 16, FontWeight.w600));
    final relation = styleOf(friendReviewRelationLabel);
    expect((relation.color, relation.fontSize, relation.fontWeight), (AppColors.muted, 12, FontWeight.w400));
    final tag = styleOf('약속을 잘 지켜요');
    expect((tag.color, tag.fontSize, tag.fontWeight), (AppColors.primaryText, 12, FontWeight.w600));
    final body = styleOf(_comment);
    expect((body.color, body.fontSize, body.fontWeight), (AppColors.body, 14, FontWeight.w400));
  });

  test('관계 문구는 고정 "친구"(pen iFxLX — DB · API 에 관계 칸이 없고 친구 코드로도 쓴다)', () {
    expect(friendReviewRelationLabel, '친구');
  });

  testWidgets('학교가 없으면 배지 없이 이니셜이 맨 앞이다', (tester) async {
    await pump(tester, pen(university: null));

    expect(find.text('서'), findsNothing);
    expect(box(tester, '달').left - tester.getRect(find.byType(FriendReviewCard)).left, 16);
  });

  // pen S0MR2b/NUNSp 36×36 #FFFFFF hairline 1 r8, 안에 DHWAj 로고 28×28 contain 가운데.
  testWidgets('로고가 있는 학교는 흰 36 칸(hairline 1 · r8) 가운데에 로고 28×28 contain, 첫 글자는 없다', (tester) async {
    await pump(tester, pen(), logos: const {'서울대학교': _logoUrl}, client: _pending());

    final logo = _picture(_logoUrl);
    expect(logo, findsOneWidget);
    expect(find.text('서'), findsNothing);
    expect(tester.getSize(logo), const Size(28, 28));
    expect(tester.widget<Image>(_networkImage(_logoUrl)).fit, BoxFit.contain);
    final badge = find.ancestor(of: logo, matching: find.byType(Container)).first;
    expect(tester.getSize(badge), const Size(36, 36));
    expect(tester.getCenter(logo), tester.getCenter(badge));
    final card = tester.getRect(find.byType(FriendReviewCard));
    expect(tester.getTopLeft(badge) - card.topLeft, const Offset(16, 22));
    final container = tester.widget<Container>(badge);
    expect((container.decoration! as BoxDecoration).color, AppColors.canvas);
    expect((container.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(8));
    final border = (container.foregroundDecoration! as BoxDecoration).border! as Border;
    expect((border.top.color, border.top.width), (AppColors.hairline, 1));
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('로고를 못 불러오면 검정 첫 글자 칸(surfaceInk)으로 바뀐다', (tester) async {
    await pump(tester, pen(), logos: const {'서울대학교': _logoUrl}, client: _failing());

    expect(find.text('서'), findsOneWidget);
    final badge = find.ancestor(of: find.text('서'), matching: find.byType(Container)).first;
    expect(tester.getSize(badge), const Size(36, 36));
    expect((tester.widget<Container>(badge).decoration! as BoxDecoration).color, AppColors.surfaceInk);
    debugNetworkImageHttpClientProvider = null;
  });

  // pen S0MR2b/dTmnd 36 원 #FFF0F2 clip, 안에 f76zn 아바타 36×36 cover. 이니셜(e1cLm)은 꺼진다.
  testWidgets('아바타가 있으면 36 원 안에 cover 로 그리고 닉네임 첫 글자는 없다', (tester) async {
    await pump(tester, pen(avatarUrl: _avatarUrl), client: _pending());

    final avatar = _picture(_avatarUrl);
    expect(avatar, findsOneWidget);
    expect(find.text('달'), findsNothing);
    expect(tester.getSize(avatar), const Size(36, 36));
    expect(tester.widget<Image>(_networkImage(_avatarUrl)).fit, BoxFit.cover);
    final clip = find.ancestor(of: avatar, matching: find.byType(ClipOval));
    expect(tester.getSize(clip), const Size(36, 36));
    final circle = find.ancestor(of: avatar, matching: find.byType(Container)).first;
    final decoration = tester.widget<Container>(circle).decoration! as BoxDecoration;
    expect((decoration.shape, decoration.color), (BoxShape.circle, AppColors.primaryWash));
    // 머리 줄 자리는 이니셜 때와 같다 — 배지 → 10 → 아바타 → 10 → 이름.
    final badge = box(tester, '서');
    expect(tester.getRect(avatar).left - badge.right, 10);
    expect(tester.getRect(find.text('달빛')).left - tester.getRect(avatar).right, 10);
    expect(tester.getCenter(avatar).dy, badge.center.dy);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('아바타가 없으면 닉네임 첫 글자 — 연분홍 원 36 에 14/700 primaryText', (tester) async {
    await pump(tester, pen());

    expect(find.byType(ClipOval), findsNothing);
    final initial = tester.widget<Text>(find.text('달'));
    expect((initial.style!.fontSize, initial.style!.fontWeight, initial.style!.color),
        (14, FontWeight.w700, AppColors.primaryText));
    expect(box(tester, '달').size, const Size(36, 36));
  });

  testWidgets('아바타를 못 불러오면 닉네임 첫 글자 원으로 바뀐다', (tester) async {
    await pump(tester, pen(avatarUrl: _avatarUrl), client: _failing());

    expect(find.text('달'), findsOneWidget);
    expect(box(tester, '달').size, const Size(36, 36));
    expect((tester.widget<Container>(find.ancestor(of: find.text('달'), matching: find.byType(Container)).first)
            .decoration! as BoxDecoration)
        .color, AppColors.primaryWash);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('글자 배율 2.4 에서도 학교 칸 · 아바타는 36 그대로(첫 글자 상태)', (tester) async {
    await pump(tester, pen(), onReport: () {}, width: 288, scale: 2.4);

    expect(tester.takeException(), isNull);
    expect(box(tester, '서').size, const Size(36, 36));
    expect(box(tester, '달').size, const Size(36, 36));
  });

  testWidgets('글자 배율 2.4 에서도 학교 칸 · 아바타는 36 그대로(그림 상태)', (tester) async {
    await pump(tester, pen(avatarUrl: _avatarUrl), onReport: () {}, width: 288, scale: 2.4,
        logos: const {'서울대학교': _logoUrl}, client: _pending());

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.ancestor(of: _picture(_logoUrl), matching: find.byType(Container)).first),
        const Size(36, 36));
    expect(tester.getSize(find.ancestor(of: _picture(_avatarUrl), matching: find.byType(ClipOval))),
        const Size(36, 36));
    debugNetworkImageHttpClientProvider = null;
  });

  // 학교 이름은 카드 어디에도 글자로 없어 배지가 읽는다. 닉네임은 옆 이름 글자가 읽으니 아바타 · 첫 글자는 읽지 않는다(두 번 읽힘).
  for (final withPictures in [false, true]) {
    testWidgets('낭독 — 학교 칸은 학교 이름, 닉네임은 한 번, 첫 글자는 읽지 않는다(그림 $withPictures)', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, pen(avatarUrl: withPictures ? _avatarUrl : null),
          logos: withPictures ? const {'서울대학교': _logoUrl} : const {}, client: withPictures ? _pending() : null);

      expect(find.bySemanticsLabel('서울대학교'), findsOneWidget);
      expect(find.bySemanticsLabel('달빛'), findsOneWidget);
      expect(find.bySemanticsLabel('서'), findsNothing);
      expect(find.bySemanticsLabel('달'), findsNothing);
      semantics.dispose();
      debugNetworkImageHttpClientProvider = null;
    });
  }

  testWidgets('한마디가 없으면 본문 줄과 그 위 간격 12 가 없다(높이 123)', (tester) async {
    await pump(tester, pen(comment: null));

    expect(tester.getSize(find.byType(FriendReviewCard)).height, 16 + 48 + 12 + 31 + 16);
  });

  Finder siren() => find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.siren);

  testWidgets('onReport 가 없으면 신고 버튼(사이렌 · 신고하기)이 없다', (tester) async {
    await pump(tester, pen());

    expect(siren(), findsNothing);
    expect(find.text('신고하기'), findsNothing);
    expect(find.byIcon(AppIcons.flag), findsNothing);
  });

  // pen S0MR2b/qRvp8 Report Review 48×48 세로 gap 2 가운데: aXNKI 사이렌 22(jsi9g) + o1niSD "신고하기" 9/600 #6E5861 lh1.
  testWidgets('onReport 가 있으면 깃발이 아니라 사이렌 22 + "신고하기" 9/600 #6E5861, 누름칸 48×48, 누르면 한 번 불린다', (tester) async {
    var reported = 0;
    await pump(tester, pen(), onReport: () => reported += 1);

    expect(find.byIcon(AppIcons.flag), findsNothing);
    expect(siren(), findsOneWidget);
    expect(tester.getSize(siren()), const Size(22, 22));
    final label = tester.widget<Text>(find.text('신고하기'));
    expect((label.style!.fontSize, label.style!.fontWeight, label.style!.color), (9, FontWeight.w600, const Color(0xFF6E5861)));
    // 렌더 34×9, 사이렌 아래 간격 2, 같은 가운데 줄.
    final labelBox = tester.getRect(find.text('신고하기'));
    final sirenBox = tester.getRect(siren());
    expect(labelBox.top - sirenBox.bottom, 2);
    expect(labelBox.center.dx, sirenBox.center.dx);

    final button = find.ancestor(of: siren(), matching: find.byType(InkResponse));
    final cell = tester.getRect(button);
    expect(cell.size, const Size(48, 48));
    final card = tester.getRect(find.byType(FriendReviewCard));
    expect(card.right - cell.right, 16);
    expect(cell.top - card.top, 16);
    await tester.tap(button);
    expect(reported, 1);
  });

  testWidgets('신고 버튼 낭독은 "신고하기" 버튼 하나다(사이렌 그림은 읽지 않는다)', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, pen(), onReport: () {});

    expect(
      tester.getSemantics(find.ancestor(of: siren(), matching: find.byType(InkResponse))),
      isSemantics(label: '신고하기', isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  testWidgets('글자 배율 2.0 에서도 신고 버튼 누름칸은 48 아래로 줄지 않는다', (tester) async {
    await pump(tester, pen(), onReport: () {}, width: 288, scale: 2);

    final cell = tester.getRect(find.ancestor(of: siren(), matching: find.byType(InkResponse)));
    expect(cell.width, greaterThanOrEqualTo(48));
    expect(cell.height, greaterThanOrEqualTo(48));
  });

  // 20e(pen `FEysN` 카드 v6BbW · kwBwj): 같은 누름칸 qRvp8 자리에 trash-2(E1Qfy7) 20 #6A6A6A.
  testWidgets('onDelete 가 있으면 깃발 자리에 휴지통 20 muted · 누름칸 48×48, 낭독 "리뷰 지우기", 누르면 한 번 불린다', (tester) async {
    final semantics = tester.ensureSemantics();
    var deleted = 0;
    await pump(tester, pen(), onDelete: () => deleted += 1);

    expect(siren(), findsNothing);
    expect(find.text('신고하기'), findsNothing);
    final trash = tester.widget<Icon>(find.byIcon(AppIcons.trash2));
    expect((trash.size, trash.color), (20, AppColors.muted));
    final button = find.ancestor(of: find.byIcon(AppIcons.trash2), matching: find.byType(IconButton));
    final cell = tester.getRect(button);
    expect(cell.size, const Size(48, 48));
    final card = tester.getRect(find.byType(FriendReviewCard));
    expect(card.right - cell.right, 16);
    expect(cell.top - card.top, 16);
    // 낭독기는 툴팁을 읽는다(20c 깃발 "신고하기" 와 같은 방식).
    expect(tester.getSemantics(button), isSemantics(tooltip: '리뷰 지우기', isButton: true, hasTapAction: true));
    await tester.tap(button);
    expect(deleted, 1);
    semantics.dispose();
  });

  testWidgets('태그 3개가 좁은 폭(288)에서 넘치지 않고 다음 줄로 내려간다', (tester) async {
    await pump(tester, pen(tags: const ['이야기를 잘 들어줘요', '유머 감각이 좋아요', '리액션이 좋아요']), width: 288);

    expect(tester.takeException(), isNull);
    expect(box(tester, '리액션이 좋아요').top, greaterThan(box(tester, '이야기를 잘 들어줘요').bottom));
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다.
  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      await pump(tester, pen(), onReport: () {}, width: 288, scale: scale);

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
