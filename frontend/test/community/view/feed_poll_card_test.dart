import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/feed_poll_card.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_community_repository.dart';

/// pen `IFUWA` PollCard · Feed(Z54et > Row L `qxNOz` > 76) · 17A `FBT9K` · 17A-2 `O8hjge`.
/// 글자 상자 높이는 pen 속성이 없는 곳은 렌더 값(익명 19 · 시간 16 · 참여자 16)으로 잰다.
void main() {
  final now = DateTime(2026, 9, 27, 14);
  final siren = find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.siren);
  Finder reportButton() => find.ancestor(of: siren, matching: find.byType(InkResponse)).first;

  Future<void> pumpCard(
    WidgetTester tester,
    Poll poll, {
    double width = 328,
    bool isVoting = false,
    void Function(PollChoice choice)? onVote,
    VoidCallback? onOpen,
    VoidCallback? onMore,
    bool withReport = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: FeedPollCard(
                  poll: poll,
                  now: now,
                  isVoting: isVoting,
                  onVote: onVote ?? (_) {},
                  onOpen: onOpen ?? () {},
                  onMore: onMore,
                  onReport: onMore == null && withReport ? () {} : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect card(WidgetTester tester) => tester.getRect(find.byType(FeedPollCard));

  group('카드 틀 · 머리줄', () {
    testWidgets('흰 바탕 · 모서리 24(radius.lg) · 그림자 #00000014 (0,1) 8', (tester) async {
      await pumpCard(tester, pollFixture());
      final frame = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(FeedPollCard), matching: find.byType(DecoratedBox)).first,
      );
      final decoration = frame.decoration as ShapeDecoration;
      expect(decoration.color, AppColors.canvas);
      expect((decoration.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppRadius.lg));
      expect(decoration.shadows, const [BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 8)]);
    });

    testWidgets('아바타 40(원 primary-wash + 3D 프로필 24) · 간격 10 · "익명" 14/600 · 시간 12/500 · 신고 48 오른쪽 끝(W37Xp · l169Bi · zxZNL · U6b2tA)', (tester) async {
      await pumpCard(tester, pollFixture());
      final box = card(tester);
      final avatar = tester.getRect(find.byKey(FeedPollCard.avatarKey));
      expect(avatar.size, const Size(40, 40));
      expect(avatar.topLeft - box.topLeft, const Offset(16, 16 + 4)); // 머리줄 48 가운데
      final avatarDecoration = tester.widget<Container>(find.byKey(FeedPollCard.avatarKey)).decoration! as BoxDecoration;
      expect((avatarDecoration.color, avatarDecoration.shape), (AppColors.primaryWash, BoxShape.circle));
      final icon = find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.userRound);
      expect(tester.getSize(icon), const Size(24, 24));
      expect(tester.getCenter(icon), avatar.center);

      final name = tester.getRect(find.text('익명'));
      final time = tester.getRect(find.text('방금 전'));
      expect(name.left - avatar.right, 10);
      expect(name.height, 19);
      expect(time.top, name.bottom);
      expect(time.height, 16);
      expect((name.top + time.bottom) / 2, closeTo(avatar.center.dy, 0.01));
      final nameStyle = tester.widget<Text>(find.text('익명')).style!;
      expect((nameStyle.fontSize, nameStyle.fontWeight, nameStyle.color), (14, FontWeight.w600, AppColors.ink));
      final timeStyle = tester.widget<Text>(find.text('방금 전')).style!;
      expect((timeStyle.fontSize, timeStyle.fontWeight, timeStyle.color), (12, FontWeight.w500, AppColors.muted));

      final report = tester.getRect(reportButton());
      expect(report.size, const Size(48, 48));
      expect(report.right, box.right - 16);
      expect(report.center.dy, avatar.center.dy);
    });

    testWidgets('내 글은 신고 대신 … (터치 48, 같은 자리)', (tester) async {
      var opened = 0;
      await pumpCard(tester, pollFixture(isMine: true), onMore: () => opened++);
      expect(siren, findsNothing);
      final more = tester.getRect(find.ancestor(of: find.byTooltip('더보기'), matching: find.byType(IconButton)));
      expect(more.size, const Size(48, 48));
      expect(more.right, card(tester).right - 16);
      await tester.tap(find.byTooltip('더보기'));
      expect(opened, 1);
    });

    testWidgets('질문 18/700 줄높이 1.4 · 자간 -0.18 · ink, 머리줄 아래 12, 목록은 2줄 말줄임(UkAVk)', (tester) async {
      await pumpCard(tester, pollFixture(question: '가' * 80));
      final question = tester.widget<Text>(find.text('가' * 80));
      final style = question.style!;
      expect((style.fontSize, style.fontWeight, style.height, style.letterSpacing, style.color),
          (18, FontWeight.w700, 1.4, -0.18, AppColors.ink));
      expect((question.maxLines, question.overflow), (2, TextOverflow.ellipsis));
      expect(tester.getRect(find.text('가' * 80)).top - card(tester).top, 16 + 48 + 12);
    });
  });

  group('투표 전', () {
    testWidgets('O/X 알약 56 · 사이 8 · 가운데 VS 32 흰 원(그림자 #00000026 (0,1) 4) · "VS" 12/700(MfEEJ · UMCB0 · LQaGL)', (tester) async {
      await pumpCard(tester, pollFixture(aCount: 0, bCount: 0));
      final blue = tester.getRect(find.widgetWithIcon(FilledButton, AppIcons.circle));
      final red = tester.getRect(find.widgetWithIcon(FilledButton, AppIcons.x));
      expect(blue.size, const Size(144, 56));
      expect(red.left - blue.right, 8);
      expect(blue.top - tester.getRect(find.text('첫 데이트 더치페이')).bottom, 12);

      final badge = tester.getRect(find.byKey(FeedPollCard.vsBadgeKey));
      expect(badge.size, const Size(32, 32));
      expect(badge.center, Offset((blue.left + red.right) / 2, blue.center.dy));
      final decoration = tester.widget<Container>(find.byKey(FeedPollCard.vsBadgeKey)).decoration! as BoxDecoration;
      expect((decoration.color, decoration.shape), (AppColors.canvas, BoxShape.circle));
      expect(decoration.boxShadow, const [BoxShadow(color: Color(0x26000000), offset: Offset(0, 1), blurRadius: 4)]);
      final vs = tester.widget<Text>(find.text('VS')).style!;
      expect((vs.fontSize, vs.fontWeight, vs.color), (12, FontWeight.w700, AppColors.ink));
    });

    testWidgets('낭독기는 찬성 · 반대 버튼만 읽고 VS 는 읽지 않는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester, pollFixture());
      expect(find.bySemanticsLabel('찬성'), findsOneWidget);
      expect(find.bySemanticsLabel('반대'), findsOneWidget);
      expect(find.bySemanticsLabel('VS'), findsNothing);
      semantics.dispose();
    });

    testWidgets('VS 배지가 누름을 가로채지 않는다 — 가운데 가까이 눌러도 그 쪽으로 투표', (tester) async {
      final votes = <PollChoice>[];
      await pumpCard(tester, pollFixture(), onVote: votes.add);
      final blue = tester.getRect(find.widgetWithIcon(FilledButton, AppIcons.circle));
      await tester.tapAt(Offset(blue.right - 6, blue.center.dy)); // VS 배지(가운데 32) 아래
      await tester.tap(find.byIcon(AppIcons.x));
      expect(votes, [PollChoice.a, PollChoice.b]);
    });

    testWidgets('투표 중이면 두 칸이 꺼진다(되돌릴 수 없는 투표가 두 번 가지 않게)', (tester) async {
      await pumpCard(tester, pollFixture(), isVoting: true);
      for (final button in tester.widgetList<FilledButton>(find.byType(FilledButton))) {
        expect(button.onPressed, isNull);
      }
    });

    testWidgets('직접 적은 선택지도 같은 알약 56 글자 칸 + VS(CustomVoteRow a7GPE)', (tester) async {
      await pumpCard(tester, pollFixture(optionA: '치킨', optionB: '피자'));
      expect(tester.getSize(find.widgetWithText(FilledButton, '치킨')), const Size(144, 56));
      expect(tester.getSize(find.widgetWithText(FilledButton, '피자')).height, 56);
      expect(find.byKey(FeedPollCard.vsBadgeKey), findsOneWidget);
    });

    testWidgets('투표 전 결과 한 줄(사용자 결정 4-1): 버튼 아래 12 · 12/400 muted 가운데, 아무도 안 눌렀으면 없다', (tester) async {
      await pumpCard(tester, pollFixture(aCount: 5, bCount: 3));
      final line = find.text('찬성 63% · 반대 37%');
      expect(line, findsOneWidget);
      expect(tester.getRect(line).top - tester.getRect(find.widgetWithIcon(FilledButton, AppIcons.circle)).bottom, 12);
      final style = tester.widget<Text>(line).style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, AppColors.muted));

      await pumpCard(tester, pollFixture(aCount: 0, bCount: 0));
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('아래 줄', () {
    testWidgets('구분선 1 #EBEBEB(위아래 12) · 사람 16 + "N명 참여" 12/500 muted · 높이 48 · 카드 아래 안쪽 12(X93Ip · OXJyX)', (tester) async {
      await pumpCard(tester, pollFixture(aCount: 0, bCount: 0));
      final box = card(tester);
      final line = tester.getRect(find.byKey(FeedPollCard.separatorKey));
      expect((line.left, line.right, line.height), (box.left + 16, box.right - 16, 1));
      expect(tester.widget<ColoredBox>(find.byKey(FeedPollCard.separatorKey)).color, AppColors.hairlineSoft);
      expect(line.top - tester.getRect(find.widgetWithIcon(FilledButton, AppIcons.circle)).bottom, 12);

      final people = tester.getRect(find.byIcon(AppIcons.users));
      final caption = tester.getRect(find.text('0명 참여'));
      expect(people.size, const Size(16, 16));
      expect(tester.widget<Icon>(find.byIcon(AppIcons.users)).color, AppColors.muted);
      expect(people.left, box.left + 16);
      expect(caption.left - people.right, 6);
      expect(caption.height, 16);
      final style = tester.widget<Text>(find.text('0명 참여')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w500, AppColors.muted));
      // 줄은 누름 48 — pen 44 + 아래 안쪽 16 = 48 + 12 로 카드 높이는 pen 과 같다.
      expect(caption.center.dy - line.bottom, 12 + 24);
      expect(box.bottom - (line.bottom + 12 + 48), 12);
      // 질문 1줄(18 × 1.4 = 25.2, 시험 글꼴은 25 로 반올림) 카드: 16 + 48 + 12 + 질문 + 12 + 56 + 12 + 1 + 12 + 48 + 12.
      final question = tester.getSize(find.text('첫 데이트 더치페이')).height;
      expect(question, closeTo(25.2, 0.5));
      expect(box.height, closeTo(16 + 48 + 12 + question + 12 + 56 + 12 + 1 + 12 + 48 + 12, 0.01));
    });

    testWidgets('"자세히 보기" 는 오른쪽 끝(안쪽 8) · 누름 48 → 17c(onOpen)', (tester) async {
      var opened = 0;
      await pumpCard(tester, pollFixture(), onOpen: () => opened++);
      final ink = find.ancestor(of: find.text('자세히 보기'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(ink).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(find.byIcon(AppIcons.chevronRight)).right, card(tester).right - 16 - 8);
      await tester.tap(find.text('자세히 보기'));
      expect(opened, 1);
    });

    testWidgets('눌림 효과는 카드 안에 그려진다(COMMON §4-2)', (tester) async {
      await pumpCard(tester, pollFixture());
      final ink = find.ancestor(of: find.text('자세히 보기'), matching: find.byType(InkWell)).first;
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(find.byType(FeedPollCard)));
    });
  });

  group('결과(투표 뒤)', () {
    final voted = pollFixture(aCount: 5, bCount: 3, myChoice: PollChoice.a); // 63% · 37%

    testWidgets('이긴 쪽 32/700 ink · 진 쪽 24 body, 버튼은 없다(q5v9f · SVRCr)', (tester) async {
      await pumpCard(tester, voted);
      final win = tester.widget<Text>(find.text('63%')).style!;
      final lose = tester.widget<Text>(find.text('37%')).style!;
      expect((win.fontSize, win.fontWeight, win.height, win.letterSpacing, win.color), (32, FontWeight.w700, 1.2, -0.64, AppColors.ink));
      expect((lose.fontSize, lose.color), (24, AppColors.body));
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(PollDonut), findsNothing);
      // 두 숫자는 아래가 맞는다(ScoreRow alignItems end), A 왼쪽 · B 오른쪽.
      expect(tester.getRect(find.text('63%')).bottom, tester.getRect(find.text('37%')).bottom);
      expect(tester.getRect(find.text('63%')).left, card(tester).left + 16);
      expect(tester.getRect(find.text('37%')).right, card(tester).right - 16);
    });

    testWidgets('B 가 이기면 B 가 32, 동점이면 둘 다 32', (tester) async {
      await pumpCard(tester, pollFixture(aCount: 3, bCount: 5, myChoice: PollChoice.b));
      expect(tester.widget<Text>(find.text('62%')).style!.fontSize, 32);
      expect(tester.widget<Text>(find.text('38%')).style!.fontSize, 24);

      await pumpCard(tester, pollFixture(aCount: 4, bCount: 4, myChoice: PollChoice.b));
      for (final text in tester.widgetList<Text>(find.text('50%'))) {
        expect((text.style!.fontSize, text.style!.color), (32, AppColors.ink));
      }
    });

    testWidgets('점 8 파랑/분홍 + 선택지 이름 14/600 · "내 선택" 칩은 내 쪽에만(primary-wash · check 12 · 12/700 · 높이 22)', (tester) async {
      await pumpCard(tester, voted);
      Finder dot(Color color) => find.byWidgetPredicate((w) =>
          w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
          (w.decoration! as BoxDecoration).color == color);
      expect(tester.getSize(dot(pollAgreeBlue)), const Size(8, 8));
      expect(tester.getSize(dot(AppColors.primary)), const Size(8, 8));
      final label = tester.widget<Text>(find.text('찬성')).style!;
      expect((label.fontSize, label.fontWeight, label.color), (14, FontWeight.w600, AppColors.ink));

      expect(find.text('내 선택'), findsOneWidget);
      final chip = find.byKey(FeedPollCard.myPickKey);
      expect(tester.getSize(chip).height, 22);
      expect(tester.getRect(chip).left, lessThan(card(tester).center.dx)); // 찬성(A) 쪽
      expect((tester.widget<Container>(chip).decoration! as BoxDecoration).color, AppColors.primaryWash);
      final check = tester.widget<Icon>(find.byIcon(AppIcons.check));
      expect((check.size, check.color), (12, AppColors.primaryText));
      final chipText = tester.widget<Text>(find.text('내 선택')).style!;
      expect((chipText.fontSize, chipText.fontWeight, chipText.color), (12, FontWeight.w700, AppColors.primaryText));

      await pumpCard(tester, pollFixture(aCount: 5, bCount: 3, myChoice: PollChoice.b));
      expect(tester.getRect(find.byKey(FeedPollCard.myPickKey)).left, greaterThan(card(tester).center.dx));
    });

    testWidgets('쪼개짐 막대: 높이 16 · 모서리 8 · 파랑 폭 = (안쪽 − 4) × A% · 사이 4 · 숫자 아래 12(t04cX · D2xRc6 · L0CNk)', (tester) async {
      await pumpCard(tester, voted);
      final box = card(tester);
      final a = tester.getRect(find.byKey(FeedPollCard.agreeBarKey));
      final b = tester.getRect(find.byKey(FeedPollCard.disagreeBarKey));
      expect(a.height, 16);
      expect(a.left, box.left + 16);
      expect(a.width, closeTo((296 - 4) * 0.63, 0.01));
      expect(b.left - a.right, closeTo(4, 0.01));
      expect(b.right, box.right - 16);
      expect(a.top - tester.getRect(find.text('63%')).bottom, 12);
      final aBox = tester.widget<DecoratedBox>(find.byKey(FeedPollCard.agreeBarKey)).decoration as BoxDecoration;
      final bBox = tester.widget<DecoratedBox>(find.byKey(FeedPollCard.disagreeBarKey)).decoration as BoxDecoration;
      expect((aBox.color, aBox.borderRadius), (pollAgreeBlue, BorderRadius.circular(8)));
      expect(bBox.color, AppColors.primary);
      expect(tester.getRect(find.byKey(FeedPollCard.separatorKey)).top - a.bottom, 12);
    });

    testWidgets('한쪽이 0% 면 막대 하나가 끝까지 — 틈 4 가 남지 않는다', (tester) async {
      await pumpCard(tester, pollFixture(aCount: 3, bCount: 0, myChoice: PollChoice.a));
      expect(tester.getSize(find.byKey(FeedPollCard.agreeBarKey)).width, 296);
      expect(tester.getSize(find.byKey(FeedPollCard.disagreeBarKey)).width, 0);
    });

    testWidgets('낭독: 쪽마다 "이름 퍼센트" + 내 쪽은 ", 내 선택" — 색만으로 가르지 않는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester, voted);
      expect(find.bySemanticsLabel('찬성 63%, 내 선택'), findsOneWidget);
      expect(find.bySemanticsLabel('반대 37%'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('모션(17A-2 — 방금 투표한 카드만, AppMotion.standard 220ms)', () {
    Poll before() => pollFixture(aCount: 4, bCount: 3);
    Poll after() => pollFixture(aCount: 5, bCount: 3, myChoice: PollChoice.a); // 63% · 37%

    testWidgets('투표 직후: 막대가 0 에서 차오르고 숫자가 0% 부터 올라가 220ms 에 끝난다', (tester) async {
      await pumpCard(tester, before());
      await pumpCard(tester, after());
      expect(tester.getSize(find.byKey(FeedPollCard.agreeBarKey)).width, 0);
      expect(find.text('0%'), findsNWidgets(2));

      await tester.pump(const Duration(milliseconds: 110));
      final mid = tester.getSize(find.byKey(FeedPollCard.agreeBarKey)).width;
      expect(mid, inExclusiveRange(0, (296 - 4) * 0.63));
      expect(find.text('63%'), findsNothing);

      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.getSize(find.byKey(FeedPollCard.agreeBarKey)).width, closeTo((296 - 4) * 0.63, 0.01));
      expect(find.text('63%'), findsOneWidget);
      expect(find.text('37%'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('처음부터 투표한 카드(스크롤 · 새로 고침)는 움직이지 않고 바로 최종 값', (tester) async {
      await pumpCard(tester, after());
      expect(find.text('63%'), findsOneWidget);
      expect(tester.getSize(find.byKey(FeedPollCard.agreeBarKey)).width, closeTo((296 - 4) * 0.63, 0.01));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('낭독은 움직이는 동안에도 최종 값을 읽는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester, before());
      await pumpCard(tester, after());
      expect(find.bySemanticsLabel('찬성 63%, 내 선택'), findsOneWidget);
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('동작 줄이기면 방금 투표해도 바로 최종 상태(DESIGN §7)', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpCard(tester, before());
      await pumpCard(tester, after());
      expect(find.text('63%'), findsOneWidget);
      expect(tester.getSize(find.byKey(FeedPollCard.agreeBarKey)).width, closeTo((296 - 4) * 0.63, 0.01));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('어느 상태에도 하네스 금지어(환급 · 선물 · 송금 · 현금 · 출금)가 없고, 그림은 3D 아이콘뿐 — 실존 인물 사진 없음', (tester) async {
    const banned = ['환급', '선물', '송금', '현금', '출금'];
    final realPhoto = RegExp(r'(human|card-|avatar-|rail-)', caseSensitive: false);
    for (final poll in [
      pollFixture(),
      pollFixture(optionA: '치킨', optionB: '피자'),
      pollFixture(myChoice: PollChoice.a),
      pollFixture(isMine: true, myChoice: PollChoice.b),
    ]) {
      await pumpCard(tester, poll, onMore: poll.isMine ? () {} : null);
      final texts = [for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? ''];
      for (final word in banned) {
        expect(texts.where((t) => t.contains(word)), isEmpty, reason: word);
      }
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        final asset = (image.image as ResizeImage).imageProvider as AssetImage;
        expect(asset.assetName, startsWith('assets/icons/'));
        expect(realPhoto.hasMatch(asset.assetName), isFalse, reason: asset.assetName);
      }
    }
  });

  testWidgets('320 폭 · 글자 240% 에서 넘치거나 조용히 잘리지 않는다 — 기본 · 직접 적은 6자 · 결과 · 내 글', (tester) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 넘침 오류는 Flex 만 낸다 — 고정 상자에 갇힌 글자는 오류 없이 잘린다. 일부러 말줄임한 질문은 뺀다.
    List<String> clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.overflow != TextOverflow.ellipsis &&
                (p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                    p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
          p.text.toPlainText(),
    ];

    for (final poll in [
      pollFixture(question: '가' * 80),
      pollFixture(optionA: '가나다라마바', optionB: '바마라다나가'),
      pollFixture(optionA: '가나다라마바', optionB: '바마라다나가', aCount: 100, bCount: 3, myChoice: PollChoice.a),
      pollFixture(isMine: true, aCount: 5, bCount: 300, myChoice: PollChoice.b),
    ]) {
      await pumpCard(tester, poll, width: 320 - 32, onMore: poll.isMine ? () {} : null);
      expect(tester.takeException(), isNull, reason: poll.optionA);
      expect(clippedTexts(), isEmpty, reason: poll.optionA);
    }
  });
}
