import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/community_feed_screen.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../safety/model/fake_safety_repository.dart';
import '../model/fake_community_repository.dart';

void main() {
  late FakeCommunityRepository repository;
  late FakeSafetyRepository safety;

  setUp(() {
    repository = FakeCommunityRepository();
    safety = FakeSafetyRepository();
  });

  Future<void> pump(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/community',
      routes: [
        GoRoute(path: '/community', builder: (context, state) => const CommunityFeedScreen()),
        GoRoute(path: '/community/new', builder: (context, state) => const Text('쓰기')),
        GoRoute(
          path: '/community/polls/:pollId',
          builder: (context, state) => Text('상세 ${state.pathParameters['pollId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repository),
          safetyRepositoryProvider.overrideWithValue(safety),
          communityNowProvider.overrideWithValue(() => DateTime(2026, 9, 27, 14)),
          // 하단 내비 뱃지가 대화 목록 · 수락함을 읽는다.
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('글이 없으면 빈 상태(n2tqZ)', (tester) async {
    await pump(tester);
    expect(find.text('아직 질문이 없어요'), findsOneWidget);
    expect(find.text('궁금한 걸 익명으로 물어보고\n캠퍼스 사람들의 생각을 들어보세요.'), findsOneWidget);
    await tester.tap(find.text('질문 올리기'));
    await tester.pumpAndSettle();
    expect(find.text('쓰기'), findsOneWidget);
  });

  testWidgets('빈 상태 버튼 폭은 글자 + 좌우 20(pen l8vOF · Button HE8FZ padding [0,20]), 높이 52(2026-10-01 개편)', (tester) async {
    await pump(tester);
    final button = tester.getRect(find.widgetWithText(ElevatedButton, '질문 올리기'));
    final label = tester.getRect(find.text('질문 올리기'));
    expect(button.width, closeTo(label.width + 40, 0.5));
    expect(button.height, 52);
  });

  testWidgets('불러오기 실패는 빈 상태가 아니라 실패 문구와 다시 시도', (tester) async {
    repository.page = const FailureResult(ServerUnavailableFailure());
    await pump(tester);
    expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);
    expect(find.text('아직 질문이 없어요'), findsNothing);

    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.byType(PollCard), findsOneWidget);
  });

  testWidgets('투표 전: O·X 버튼과 그 아래 결과 한 줄(사용자 결정 4-1)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(aCount: 5, bCount: 3)], hasMore: false));
    await pump(tester);
    expect(find.bySemanticsLabel('찬성'), findsOneWidget);
    expect(find.bySemanticsLabel('반대'), findsOneWidget);
    expect(find.text('찬성 63% · 반대 37% · 8명 참여'), findsOneWidget);
  });

  testWidgets('커스텀 라벨이면 글자 버튼', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(optionA: '짜장', optionB: '짬뽕')], hasMore: false));
    await pump(tester);
    expect(find.widgetWithText(FilledButton, '짜장'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '짬뽕'), findsOneWidget);
  });

  testWidgets('직접 적은 선택지 버튼은 pen 규격 — 폭 144 · 높이 72 · 좌우 안쪽 8 · 파랑/빨강 · 흰 20/700(ojrC5 · yigm0 · nxuT6)', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository.page = Success(
      PollPage(polls: [pollFixture(optionA: '가나다라마바', optionB: '짬뽕')], hasMore: false),
    );
    await pump(tester);
    final buttonFinder = find.widgetWithText(FilledButton, '가나다라마바');
    final button = tester.getRect(buttonFinder);
    expect(button.size, const Size(144, 72));
    // 6자 20px(≈120)가 칸 안쪽(144 − 16 = 128)에 줄여지지 않고 한 줄로 들어간다. 안쪽 여백은 정확히 좌우 8.
    final label = tester.getRect(find.text('가나다라마바'));
    expect(label.width, lessThanOrEqualTo(144 - 16));
    expect(label.height, lessThan(30));
    expect(tester.widget<FilledButton>(buttonFinder).style!.padding!.resolve({}), const EdgeInsets.symmetric(horizontal: 8));
    // 회색(#E5E5E5) 이 아니라 O/X 와 같은 파랑 · 빨강, 글자는 흰 20/700.
    Color? fill(Finder finder) => tester.widget<FilledButton>(finder).style!.backgroundColor!.resolve({});
    expect(fill(buttonFinder), pollAgreeBlue);
    expect(fill(find.widgetWithText(FilledButton, '짬뽕')), AppColors.primary);
    final style = tester.widget<Text>(find.text('가나다라마바')).style!;
    expect((style.fontSize, style.fontWeight, style.color), (20.0, FontWeight.w700, AppColors.onPrimary));
  });

  testWidgets('O·X 칸은 직접 적은 칸과 같은 높이 72 · 같은 파랑/빨강(wHrXJ · tjZrc)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    final blue = find.widgetWithIcon(FilledButton, AppIcons.circle);
    final red = find.widgetWithIcon(FilledButton, AppIcons.x);
    expect(tester.getSize(blue).height, 72);
    expect(tester.widget<FilledButton>(blue).style!.backgroundColor!.resolve({}), pollAgreeBlue);
    expect(tester.widget<FilledButton>(red).style!.backgroundColor!.resolve({}), AppColors.primary);
  });

  testWidgets('투표 후: 도넛 · 비율 줄 · 참여자 수, 버튼은 없다. 가운데 % 는 우세한 쪽', (tester) async {
    // A 3 · B 5 → A = round(37.5) = 38, B = 100 − 38 = 62. 호는 A(38%), 가운데는 우세한 B 의 62%(대장 예외).
    repository.page = Success(
      PollPage(polls: [pollFixture(aCount: 3, bCount: 5, myChoice: PollChoice.a)], hasMore: false),
    );
    await pump(tester);
    expect(find.byType(PollDonut), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('찬성 38% · 반대 62%'), findsOneWidget);
    expect(find.text('8명 참여'), findsOneWidget);
    expect(find.bySemanticsLabel('찬성'), findsNothing);
  });

  testWidgets('결과 도넛은 버튼 색을 따른다: 회색 고리 위에 A 파랑, 이어서 B 분홍', (tester) async {
    repository.page = Success(
      PollPage(polls: [pollFixture(aCount: 3, bCount: 5, myChoice: PollChoice.a)], hasMore: false),
    );
    await pump(tester);
    expect(
      find.descendant(of: find.byType(PollDonut), matching: find.byType(CustomPaint)),
      paints
        ..arc(color: AppColors.surfaceStrong)
        ..arc(color: pollAgreeBlue)
        ..arc(color: AppColors.primary),
    );
  });

  testWidgets('pen 카드 틀: 폭 328 · 목록 위 8, 높이 투표 전 258 · 투표 후 305(RpRBi — 신고 버튼 48 머리줄 · 글자 상자 렌더 차 2 안)', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository.page = Success(
      PollPage(polls: [pollFixture(), pollFixture(id: 'p2', myChoice: PollChoice.a)], hasMore: false),
    );
    await pump(tester);

    final before = tester.getRect(find.byType(PollCard).at(0));
    final after = tester.getRect(find.byType(PollCard).at(1));
    expect(before.left, 16);
    expect(before.width, 328);
    expect(before.top, 56 + 8); // 앱바 56 + 목록 위 8(FXyNI)
    expect(after.top - before.bottom, 12); // 카드 사이 12(FXyNI)
    expect(before.height, closeTo(258, 2));
    expect(after.height, closeTo(305, 2));
    // "익명" 칩 22(LHkpo · MpYr6 속성 없음, 렌더 16), 도넛 96(raSK1).
    expect(tester.getSize(find.ancestor(of: find.text('익명').first, matching: find.byType(Container)).first).height, 22);
    expect(tester.getSize(find.byType(PollDonut)), const Size(96, 96));
    // 그림자 #00000010 (0,1) blur 6 · 모서리 14(RpRBi 값표 1004).
    final frame = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(PollCard).first, matching: find.byType(DecoratedBox)).first,
    );
    final decoration = frame.decoration as ShapeDecoration;
    expect(decoration.shadows, const [BoxShadow(color: Color(0x10000000), offset: Offset(0, 1), blurRadius: 6)]);
    expect((decoration.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(14));
  });

  testWidgets('pen 앱바: 제목 x20, + 는 터치 48 · 원 32 primary · 흰 plus 18, 오른쪽 여백 8(Iblb3 · uhk6J · I7U2Jp · zuIJJ)', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    expect(tester.getTopLeft(find.text('커뮤니티').first).dx, 20);
    final plus = find.byTooltip('질문 올리기');
    expect(tester.getCenter(plus), const Offset(360 - 8 - 24, 28));
    final circle = find.descendant(of: plus, matching: find.byType(Container)).first;
    expect(tester.getSize(circle), const Size(32, 32));
    expect((tester.widget<Container>(circle).decoration! as BoxDecoration).color, AppColors.primary);
    final icon = tester.widget<Icon>(find.descendant(of: plus, matching: find.byIcon(AppIcons.plus)));
    expect((icon.size, icon.color), (18.0, AppColors.onPrimary));
  });

  testWidgets('글이 한두 개라 화면을 못 채워도 아래로 당기면 새로 불러온다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    expect(repository.pageRequests.length, 1);
    await tester.fling(find.byType(ListView), const Offset(0, 500), 1500);
    await tester.pumpAndSettle();
    expect(repository.pageRequests.length, 2);
  });

  testWidgets('불러오기 실패와 빈 목록을 가른다 — 두 번째 쪽 실패는 목록을 지우지 않는다', (tester) async {
    repository
      ..page = Success(PollPage(polls: [for (var i = 0; i < 20; i++) pollFixture(id: 'p$i')], hasMore: true))
      ..nextPage = const FailureResult(NetworkFailure());
    await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.byType(PollCard), findsWidgets);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('O 를 누르면 a 로 투표하고 보상이면 토스트(15d-3)', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: true));
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('찬성'));
    await tester.pump();
    expect(repository.votes.single, (pollId: 'p1', choice: PollChoice.a));
    expect(find.text(pollRewardMessage), findsOneWidget);
    // 15d-3 은 글자만 — 재화 하트를 Lucide 로 그리지 않는다.
    expect(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)), findsNothing);
  });

  testWidgets('보상 토스트는 하단 내비 위 16 에 뜬다(pen NDZnK)', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: true));
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('찬성'));
    await tester.pumpAndSettle();
    final toast = tester.getRect(find.byType(AppToast));
    expect(tester.getRect(find.byType(AppBottomNav)).top - toast.bottom, 16);
    expect(toast.center.dx, 400); // 가운데(기본 테스트 화면 폭 800)
  });

  testWidgets('+ 는 17b 로 간다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    await tester.tap(find.byTooltip('질문 올리기'));
    await tester.pumpAndSettle();
    expect(find.text('쓰기'), findsOneWidget);
  });

  testWidgets('"자세히 보기" 는 17c 로 간다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();
    expect(find.text('상세 p1'), findsOneWidget);
  });

  testWidgets('"자세히 보기" 누르는 영역은 48 이다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    final ink = find.ancestor(of: find.text('자세히 보기'), matching: find.byType(InkWell)).first;
    expect(tester.getSize(ink).height, greaterThanOrEqualTo(48));
  });

  testWidgets('"자세히 보기" 글자 자리는 pen 과 같다 — 위 줄에서 12, 카드 아래에서 17 + 16 안(i5ugzn)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    final card = tester.getRect(find.byType(PollCard));
    final above = tester.getRect(find.text('찬성 63% · 반대 37% · 8명 참여'));
    final label = tester.getRect(find.text('자세히 보기'));
    expect(label.top - above.bottom, 12);
    // pen 은 카드 아래 안쪽 16. 누르는 영역 48 을 채우느라 3 까지 더 둔다.
    expect(card.bottom - label.bottom, inInclusiveRange(16, 19.5));
    expect(label.right, card.right - 16 - 2 - 14); // 오른쪽 정렬, 간격 2 + chevron 14
  });

  testWidgets('"자세히 보기" 눌림 효과는 카드 안에 그려진다(COMMON §4-2)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    await pump(tester);
    final ink = find.ancestor(of: find.text('자세히 보기'), matching: find.byType(InkWell)).first;
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.getSize(material), tester.getSize(find.byType(PollCard)));
  });

  testWidgets('폰 폭(360)에서 글자 2배 · 80자 질문 · 6자 라벨에도 넘치거나 잘리지 않는다', (tester) async {
    // 기본 800 폭에서는 버튼 한 칸이 넓어 6자 라벨이 한 줄로 들어간다 — 실기기 폭 144 로 줄여야 잡힌다.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    repository.page = Success(PollPage(polls: [
      pollFixture(question: '가' * 80, optionA: '가나다라마바', optionB: '바마라다나가'),
      pollFixture(id: 'p2', optionA: '가나다라마바', optionB: '바마라다나가', myChoice: PollChoice.b),
    ], hasMore: false));

    // 넘침 오류는 Flex 만 낸다 — 고정 상자에 갇힌 글자는 오류 없이 잘린다. 화면 전체(앱바 · 내비 포함)를 본다.
    // 일부러 말줄임한 글자(목록 질문 2줄 · 내비 "커뮤니티")는 뺀다.
    List<String> clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.overflow != TextOverflow.ellipsis &&
                (p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                    p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
          p.text.toPlainText(),
    ];

    await pump(tester);
    expect(tester.takeException(), isNull);
    final clipped = clippedTexts();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    clipped.addAll(clippedTexts());
    expect(clipped, isEmpty);

    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    // 버튼 높이 56 은 고정이라 두 줄로 꺾이면 예외 없이 조용히 잘린다 — 그려진 글자 폭이 버튼 안인지 본다.
    final button = find.ancestor(of: find.text('가나다라마바').first, matching: find.byType(FilledButton)).first;
    expect(tester.getRect(find.text('가나다라마바').first).width, lessThanOrEqualTo(tester.getRect(button).width));
  });

  testWidgets('내 글에만 … 가 있다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true), pollFixture(id: 'p2')], hasMore: false));
    await pump(tester);
    expect(find.byTooltip('더보기'), findsOneWidget);
  });

  testWidgets('pen "…": 터치 48 이 머리줄 오른쪽 끝(신고 버튼 자리), 내 글 머리줄은 48(mc9mW · 10-01 개편)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    // 툴팁은 버튼 몸체(40)만 감싼다 — 누르는 영역(48)은 IconButton 전체다.
    final more = tester.getRect(find.ancestor(of: find.byTooltip('더보기'), matching: find.byType(IconButton)));
    final time = tester.getRect(find.text('방금 전'));
    final card = tester.getRect(find.byType(PollCard));
    expect(more.size, const Size(48, 48));
    expect(more.right, card.right - 16);
    expect(more.center.dy, time.center.dy);
    // 머리줄 48 → 질문은 카드 위 안쪽 16 + 48 + 12 아래.
    expect(tester.getRect(find.text('첫 데이트 더치페이')).top - card.top, 16 + 48 + 12);
  });

  testWidgets('… → 삭제하기 → 확인 창(15d-2) 삭제하기 를 누르면 지우고 목록에서 뺀다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    expect(find.text('이 질문을 삭제할까요?'), findsOneWidget);
    expect(find.text('질문과 받은 투표가 모두 사라지고 되돌릴 수 없어요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
    await tester.pumpAndSettle();
    expect(repository.deleted, ['p1']);
    expect(find.byType(PollCard), findsNothing);
    // 15d-5 `SKQgV`: "삭제했어요" 글자만(토스트 `VuCcc` 아이콘 끔).
    expect(find.text(pollDeletedMessage), findsOneWidget);
    expect(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)), findsNothing);
  });

  Future<void> openDeleteConfirm(WidgetTester tester) async {
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
  }

  testWidgets('삭제 중(15d-2 EIEFb): 확인 시트가 열린 채 "삭제하기" 만 꺼지고, 끝나면 닫히며 "삭제했어요"', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false))
      ..holdDelete = Completer<void>();
    await pump(tester);
    await openDeleteConfirm(tester);
    final deleteButton = find.widgetWithText(ElevatedButton, '삭제하기');
    await tester.tap(deleteButton);
    await tester.pump();
    // 시트 닫힘 애니메이션보다 길게 기다려도 그대로다.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('이 질문을 삭제할까요?'), findsOneWidget);
    expect(find.byType(PollCard), findsOneWidget);
    final button = tester.widget<ElevatedButton>(deleteButton);
    expect(button.onPressed, isNull);
    // EIEFb: 채움 #E5E5E5 · 글자 #929292, 스피너 없음 — AppButton 의 꺼진 상태 그대로.
    expect(button.style!.backgroundColor!.resolve({WidgetState.disabled}), AppColors.primaryDisabled);
    expect(button.style!.foregroundColor!.resolve({WidgetState.disabled}), AppColors.disabled);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '취소')).onPressed, isNotNull);

    await tester.tap(deleteButton);
    await tester.pump();
    expect(repository.deleted.length, 1);

    repository.holdDelete!.complete();
    await tester.pumpAndSettle();
    expect(find.text('이 질문을 삭제할까요?'), findsNothing);
    expect(find.byType(PollCard), findsNothing);
    expect(find.text(pollDeletedMessage), findsOneWidget);
  });

  testWidgets('지우기 실패(15d-6 f6fXkA · 토스트 ANlRW): 시트는 닫히고 카드는 남고, 내비 위 16 · 높이 40 경고 토스트', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false))
      ..deleteResult = const FailureResult(UnknownFailure());
    await pump(tester);
    await openDeleteConfirm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
    await tester.pumpAndSettle();
    expect(find.text('이 질문을 삭제할까요?'), findsNothing);
    expect(find.byType(PollCard), findsOneWidget);
    expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
    expect(find.text(pollDeletedMessage), findsNothing);
    final icon = tester.widget<Icon>(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)));
    expect(icon.icon, AppIcons.alertTriangle);
    expect(icon.size, 16);
    final toast = tester.getRect(find.byType(AppToast));
    expect(toast.height, 40);
    expect(tester.getRect(find.byType(AppBottomNav)).top - toast.bottom, 16);
    expect(toast.center.dx, 400);
  });

  testWidgets('지우는 중 "취소" 로 닫아도 요청이 끝나면 "삭제했어요" 를 알린다(서버에서는 지워졌다)', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false))
      ..holdDelete = Completer<void>();
    await pump(tester);
    await openDeleteConfirm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, '취소'));
    await tester.pumpAndSettle();
    expect(find.text('이 질문을 삭제할까요?'), findsNothing);
    expect(find.text(pollDeletedMessage), findsNothing);

    repository.holdDelete!.complete();
    await tester.pumpAndSettle();
    expect(repository.deleted, ['p1']);
    expect(find.byType(PollCard), findsNothing);
    expect(find.text(pollDeletedMessage), findsOneWidget);
  });

  testWidgets('시트가 닫히는 도중(애니메이션)에 지우기가 끝나도 아래 화면까지 닫지 않는다', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false))
      ..holdDelete = Completer<void>();
    await pump(tester);
    await openDeleteConfirm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, '취소'));
    await tester.pump(); // 닫힘 애니메이션 첫 프레임 — 시트 State 는 아직 살아 있다.
    repository.holdDelete!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CommunityFeedScreen), findsOneWidget);
    expect(find.text(pollDeletedMessage), findsOneWidget);
  });

  testWidgets('"삭제했어요" 토스트는 하단 내비 위 16 · 높이 40 · 가운데(pen SKQgV 97×40)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    await openDeleteConfirm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
    await tester.pumpAndSettle();
    final toast = tester.getRect(find.byType(AppToast));
    expect(toast.height, 40);
    expect(tester.getRect(find.byType(AppBottomNav)).top - toast.bottom, 16);
    expect(toast.center.dx, 400); // 가운데(기본 테스트 화면 폭 800)
    // 폭 97 은 pen 글꼴 기준 — 테스트 글꼴(Ahem)에선 좌우 안쪽 16 + 글자 폭만 본다.
    expect(toast.width, tester.getSize(find.text(pollDeletedMessage)).width + 16 * 2);
  });

  testWidgets('폰 폭(360) · 글자 2배에서 "삭제했어요" 토스트도 넘치거나 잘리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    await openDeleteConfirm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final p = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byType(AppToast), matching: find.byType(RichText)),
    );
    expect(p.getMaxIntrinsicHeight(p.size.width), lessThanOrEqualTo(p.size.height + 0.5));
    expect(p.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(p.size.width + 0.5));
  });

  testWidgets('확인 창에서 취소하면 지우지 않는다', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isEmpty);
    expect(find.byType(PollCard), findsOneWidget);
  });

  testWidgets('pen 시트 높이: 메뉴 157(15d-1 ofjwb) · 확인 260(15d-2 CCdBk — 버튼 52 로 4 줄어듦, HE8FZ 2026-10-01 개편), 행 52 · 버튼 52/48', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).height, 157);
    final row = find.ancestor(of: find.text('삭제하기'), matching: find.byType(InkWell)).first;
    expect(tester.getSize(row).height, 52);

    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).height, closeTo(260, 1));
    expect(tester.getSize(find.widgetWithText(ElevatedButton, '삭제하기')).height, 52);
    expect(tester.getSize(find.widgetWithText(ElevatedButton, '취소')).height, 48);
  });

  testWidgets('폰 폭(360) · 글자 2배에서 두 시트도 넘치거나 잘리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));

    List<String> clippedInSheet() => [
      for (final element in find.descendant(of: find.byType(BottomSheet), matching: find.byType(RichText)).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
          p.text.toPlainText(),
    ];

    await pump(tester);
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final clipped = clippedInSheet();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    clipped.addAll(clippedInSheet());
    expect(clipped, isEmpty);
  });

  testWidgets('메뉴 행 눌림 효과는 시트 밖이 아니라 그 행에 그려진다(COMMON §4-2)', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true)], hasMore: false));
    await pump(tester);
    await tester.tap(find.byTooltip('더보기'));
    await tester.pumpAndSettle();
    for (final label in ['삭제하기', '취소']) {
      final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(ink), reason: label);
    }
  });

  testWidgets('끝까지 내리면 다음 쪽을 부른다', (tester) async {
    repository
      ..page = Success(PollPage(polls: [for (var i = 0; i < 20; i++) pollFixture(id: 'p$i')], hasMore: true))
      ..nextPage = const Success(PollPage(polls: [], hasMore: false));
    await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(repository.pageRequests.length, greaterThanOrEqualTo(2));
    expect(repository.pageRequests.last.beforeId, 'p19');
  });

  group('신고 버튼(A16 · pen uPUf3)', () {
    final siren = find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.siren);
    Finder reportButton() => find.ancestor(of: siren, matching: find.byType(InkResponse)).first;

    testWidgets('남의 글에만 있고, 내 글에는 신고 대신 … 만', (tester) async {
      repository.page = Success(PollPage(polls: [pollFixture(isMine: true), pollFixture(id: 'p2')], hasMore: false));
      await pump(tester);

      final cards = find.byType(PollCard);
      expect(find.descendant(of: cards.first, matching: siren), findsNothing);
      expect(find.descendant(of: cards.first, matching: find.byTooltip('더보기')), findsOneWidget);
      expect(find.descendant(of: cards.last, matching: siren), findsOneWidget);
      expect(find.descendant(of: cards.last, matching: find.byTooltip('더보기')), findsNothing);
    });

    testWidgets('터치 48 · 머리줄 오른쪽 끝, 사이렌 22 → 2 → "신고하기" 9/600 #6E5861 (OaLnA · E6FpN · Wwsmw)', (tester) async {
      repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
      await pump(tester);

      final card = tester.getRect(find.byType(PollCard));
      final button = tester.getRect(reportButton());
      expect(button.size, const Size(48, 48));
      expect(button.right, card.right - 16);
      expect(button.center.dy, tester.getCenter(find.text('방금 전')).dy);
      final icon = tester.getRect(siren);
      expect(icon.size, const Size(22, 22));
      expect(icon.center.dx, button.center.dx);
      final label = find.descendant(of: find.byType(PollCard), matching: find.text('신고하기'));
      expect(tester.getRect(label).top - icon.bottom, 2);
      final style = tester.widget<Text>(label).style!;
      expect((style.fontSize, style.fontWeight, style.color), (9, FontWeight.w600, const Color(0xFF6E5861)));
      // 아이콘 22 + 2 + 글자 9 = 33 이 48 가운데.
      expect(icon.top - button.top, 7.5);
      // 머리줄 48 → 질문은 카드 위 안쪽 16 + 48 + 12 아래.
      expect(tester.getRect(find.text('첫 데이트 더치페이')).top - card.top, 16 + 48 + 12);
    });

    testWidgets('누르면 신고 시트 → 사유 고르고 신고하기 → poll 대상으로 보내고 카드는 남는다', (tester) async {
      repository.page = Success(PollPage(polls: [pollFixture(id: 'p2')], hasMore: false));
      await pump(tester);

      await tester.tap(reportButton());
      await tester.pumpAndSettle();
      expect(find.byType(ReportSheet), findsOneWidget);
      await tester.tap(find.text('광고·스팸'));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(ReportSheet), matching: find.text('신고하기')));
      await tester.pumpAndSettle();

      expect(safety.reports.single.target, {'target_type': 'poll', 'target_id': 'p2'});
      expect(safety.reports.single.reason, ReportReason.spam);
      expect(find.byType(ReportSheet), findsNothing);
      expect(find.text('신고했어요. 운영팀이 확인할게요'), findsOneWidget);
      expect(find.byType(PollCard), findsOneWidget);
    });

    testWidgets('낭독기는 "신고하기" 버튼 하나로 읽는다', (tester) async {
      final semantics = tester.ensureSemantics();
      repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
      await pump(tester);

      expect(tester.getSemantics(reportButton()), matchesSemantics(label: '신고하기', isButton: true, hasTapAction: true, isFocusable: true, hasFocusAction: true));
      semantics.dispose();
    });

    testWidgets('폰 폭(360) · 글자 2배에서 머리줄이 넘치지 않고 "신고하기" 도 잘리지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
      await pump(tester);

      expect(tester.takeException(), isNull);
      final p = tester.renderObject<RenderParagraph>(
        find.descendant(of: reportButton(), matching: find.byType(RichText)),
      );
      expect(p.getMaxIntrinsicHeight(p.size.width), lessThanOrEqualTo(p.size.height + 0.5));
      expect(p.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(p.size.width + 0.5));
    });
  });
}
