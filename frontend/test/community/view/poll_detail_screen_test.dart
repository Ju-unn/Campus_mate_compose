import 'dart:async';

import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/model/data/poll_feed.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/view/comment_input_bar.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_detail_screen.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/community/viewmodel/poll_detail_view_model.dart';
import 'package:campus_mate/core/push/push_refresh.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/safety/model/data/report_reason.dart';
import 'package:campus_mate/safety/model/repository/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../safety/model/repository/fake_safety_repository.dart';
import '../model/repository/fake_community_repository.dart';

void main() {
  late FakeCommunityRepository repository;
  late FakeSafetyRepository safety;

  setUp(() {
    repository = FakeCommunityRepository();
    safety = FakeSafetyRepository();
  });

  /// [feedFirst] 면 피드 목록을 먼저 채운 뒤 피드 위에 17c 를 연다. 아니면 피드 없이 pollId 만으로 연다(푸시 알림).
  Future<ProviderContainer> pumpDetail(WidgetTester tester, String pollId, {bool feedFirst = true}) async {
    final container = ProviderContainer(
      overrides: [
        communityRepositoryProvider.overrideWithValue(repository),
        safetyRepositoryProvider.overrideWithValue(safety),
        communityNowProvider.overrideWithValue(() => DateTime(2026, 9, 27, 14)),
      ],
    );
    addTearDown(container.dispose);
    if (feedFirst) {
      container.read(communityFeedViewModelProvider);
      await container.read(communityFeedViewModelProvider.notifier).refresh();
    }

    final router = GoRouter(
      initialLocation: '/community',
      routes: [
        GoRoute(path: '/community', builder: (context, state) => const Text('피드')),
        GoRoute(
          path: '/community/polls/:pollId',
          builder: (context, state) => PollDetailScreen(pollId: state.pathParameters['pollId']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    unawaited(router.push('/community/polls/$pollId'));
    await tester.pumpAndSettle();
    return container;
  }

  /// 푸시가 왔을 때 앱이 하는 일(`main.dart` · 알림함과 같은 호출).
  void receivePush(ProviderContainer container, Map<String, dynamic> data) =>
      refreshForPush(container.read, data, invalidate: container.invalidate, exists: container.exists);

  Finder inputField() => find.descendant(of: find.byType(CommentInputBar), matching: find.byType(TextField));

  /// 댓글 "…" → 신고하기 → 사유 → 보내기까지 눌러 신고 완료 토스트를 띄운다.
  Future<void> reportCommentThrough(WidgetTester tester, String commentId) async {
    await tester.tap(find.descendant(of: find.byKey(ValueKey('comment-$commentId')), matching: find.byTooltip('더보기')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('신고하기')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('광고·스팸'));
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(ReportSheet), matching: find.text('신고하기')));
    await tester.pumpAndSettle();
  }

  /// 피드에도 같은 글을 두고, 상세가 읽는 글도 같게 맞춘다.
  void givenPoll(Poll poll) {
    repository
      ..page = Success(PollPage(polls: [poll], hasMore: false))
      ..poll = Success(poll);
  }

  void givenComments(List<PollComment> comments, {bool hasMore = false}) =>
      repository.commentPage = Success(PollCommentPage(comments: comments, hasMore: hasMore));

  Finder rowOf(String id) => find.byKey(ValueKey('comment-$id'));
  Finder moreOf(String id) => find.descendant(of: rowOf(id), matching: find.byTooltip('더보기'));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('17c: 제목 "투표 상세", 피드 카드와 같은 크기, 질문 전문', (tester) async {
    givenPoll(pollFixture(question: '가' * 80, myChoice: PollChoice.a));
    await pumpDetail(tester, 'p1');
    expect(find.text('투표 상세'), findsOneWidget);
    expect(tester.getSize(find.byType(PollDonut)), const Size(96, 96));
    expect(find.text('자세히 보기'), findsNothing);
    expect(tester.widget<Text>(find.text('가' * 80)).maxLines, isNull);
  });

  testWidgets('상세에서도 투표 전이면 투표할 수 있다(사용자 결정 4)', (tester) async {
    givenPoll(pollFixture());
    repository.voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.b), rewarded: false));
    await pumpDetail(tester, 'p1');
    repository.poll = Success(pollFixture(myChoice: PollChoice.b));
    await tester.tap(find.bySemanticsLabel('반대'));
    await tester.pumpAndSettle();
    expect(repository.votes.single.choice, PollChoice.b);
    expect(find.byType(PollDonut), findsOneWidget);
  });

  testWidgets('글을 읽을 수 없으면(404) 찾을 수 없다고 말한다', (tester) async {
    repository.poll = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'));
    repository.commentPage = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'));
    await pumpDetail(tester, 'gone', feedFirst: false);
    expect(find.text('질문을 찾을 수 없어요'), findsOneWidget);
    expect(find.byType(CommentInputBar), findsNothing);
  });

  testWidgets('알림에서 바로 들어와도(피드 없음) pollId 로 글을 읽어 보여 준다', (tester) async {
    givenPoll(pollFixture(id: 'p9', question: '알림으로 온 질문', commentCount: 1));
    givenComments([commentFixture(id: 'c1', body: '첫 댓글')]);
    await pumpDetail(tester, 'p9', feedFirst: false);

    expect(repository.fetchedPollIds, ['p9']);
    expect(repository.commentRequests.single.pollId, 'p9');
    expect(find.text('알림으로 온 질문'), findsOneWidget);
    expect(find.text('첫 댓글'), findsOneWidget);
  });

  testWidgets(
    'pen 17c: 제목 x60 · 뒤로 arrow-left 22, 본문 안쪽 16, 카드 276(신고 버튼 48 머리줄), 카드 아래 16 뒤에 댓글 머리(bcnJx · ZR52B · y0uSd4 · Comments Section)',
    (tester) async {
      phone(tester);
      givenPoll(pollFixture(myChoice: PollChoice.a, commentCount: 12));
      await pumpDetail(tester, 'p1');

      expect(tester.getTopLeft(find.text('투표 상세')).dx, 60);
      expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft)).size, 22);
      final card = tester.getRect(find.byType(PollCard));
      expect(card.topLeft, const Offset(16, 56 + 16));
      expect(card.width, 328);
      expect(card.height, closeTo(276, 2));
      // Comments Section: 카드 아래 간격 16 → 머리 "댓글 12" 18/700 ink(렌더 높이 25, Ymhdq) → 간격 8 → 목록.
      final header = find.text('댓글 12');
      expect(tester.getRect(header).top, closeTo(card.bottom + 16, 0.5));
      expect(tester.getRect(header).height, closeTo(25, 0.5));
      expect(tester.getRect(header).left, 16);
      final style = tester.widget<Text>(header).style!;
      expect((style.fontSize, style.fontWeight, style.color), (18, FontWeight.w700, AppColors.ink));
    },
  );

  final siren = find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.siren);

  testWidgets('17c 도 남의 글이면 머리줄 오른쪽 끝에 신고 버튼이 있다(A16 · uPUf3)', (tester) async {
    givenPoll(pollFixture());
    await pumpDetail(tester, 'p1');

    final button = tester.getRect(find.ancestor(of: siren, matching: find.byType(InkResponse)).first);
    expect(button.size, const Size(48, 48));
    expect(button.right, tester.getRect(find.byType(PollCard)).right - 16);
  });

  testWidgets('17c 내 글이면 신고 버튼이 없다', (tester) async {
    givenPoll(pollFixture(isMine: true));
    await pumpDetail(tester, 'p1');

    expect(siren, findsNothing);
  });

  group('댓글 목록(pen X4HnyK · S8tPtZ · CommentRow f37XJH)', () {
    testWidgets('익명N 이름, 글쓴이 댓글에는 "글쓴이" 배지, 상대 시간 — 같은 사람은 같은 번호', (tester) async {
      givenPoll(pollFixture(commentCount: 3));
      givenComments([
        commentFixture(id: 'c1', aliasNo: null, isPostAuthor: true, body: '글쓴이의 말', createdAt: DateTime(2026, 9, 27, 12)),
        commentFixture(id: 'c2', aliasNo: 2, body: '둘째 사람', createdAt: DateTime(2026, 9, 27, 13, 6)),
        commentFixture(id: 'c3', aliasNo: 2, body: '둘째 사람 또', createdAt: DateTime(2026, 9, 27, 13, 57)),
      ]);
      await pumpDetail(tester, 'p1');

      expect(find.descendant(of: rowOf('c1'), matching: find.text('글쓴이')), findsOneWidget);
      // 글쓴이는 번호가 없다(서버 alias_no null) — 글 카드와 같은 "익명" 에 배지를 붙인다.
      expect(find.descendant(of: rowOf('c1'), matching: find.text('익명')), findsOneWidget);
      expect(find.descendant(of: rowOf('c1'), matching: find.text('2시간 전')), findsOneWidget);
      expect(find.descendant(of: rowOf('c2'), matching: find.text('익명2')), findsOneWidget);
      expect(find.descendant(of: rowOf('c2'), matching: find.text('글쓴이')), findsNothing);
      expect(find.descendant(of: rowOf('c3'), matching: find.text('익명2')), findsOneWidget);
      expect(find.descendant(of: rowOf('c3'), matching: find.text('3분 전')), findsOneWidget);
      expect(find.text('댓글 3'), findsOneWidget);
    });

    testWidgets('pen CommentRow: 폭 328 · 한 줄 본문 높이 74 · 이름 14/600 · 시간 12/500 muted · 본문 14/ink · "…" 48', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c1', aliasNo: 1, body: '한 줄 본문', createdAt: DateTime(2026, 9, 27, 13))]);
      await pumpDetail(tester, 'p1');

      final row = tester.getRect(rowOf('c1'));
      expect(row.width, 328);
      expect(row.height, closeTo(74, 1));
      final name = tester.widget<Text>(find.text('익명1')).style!;
      expect((name.fontSize, name.fontWeight, name.color), (14, FontWeight.w600, AppColors.ink));
      final time = tester.widget<Text>(find.text('1시간 전')).style!;
      expect((time.fontSize, time.fontWeight, time.color), (12, FontWeight.w500, AppColors.muted));
      final body = tester.widget<Text>(find.text('한 줄 본문')).style!;
      expect((body.fontSize, body.color), (14, AppColors.ink));
      // 이름 줄(24) 높이, 본문은 이름 줄 아래 간격 4.
      expect(tester.getRect(find.text('익명1')).center.dy, closeTo(row.top + 12 + 12, 1));
      expect(tester.getRect(find.text('한 줄 본문')).top, closeTo(row.top + 12 + 24 + 4, 1));
      // "…" 누름 48 이 줄 오른쪽 끝, 이름 줄 위로 12 삐져나와 줄 맨 위에서 시작한다(H0cgQw @280,-12).
      final more = tester.getRect(moreOf('c1'));
      expect(more.size, const Size(48, 48));
      expect(more.right, row.right);
      expect(more.top, row.top);
    });

    testWidgets('폰 폭(360) · 글자 2배에서도 머리줄이 줄바꿈될 뿐 넘치지 않고 "…" 와 겹치지 않는다', (tester) async {
      phone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      givenPoll(pollFixture(commentCount: 1));
      givenComments([
        commentFixture(id: 'c1', aliasNo: null, isPostAuthor: true, canDelete: true, body: '가나다라마바사 ' * 12, createdAt: DateTime(2026, 9, 27, 13)),
      ]);
      await pumpDetail(tester, 'p1');

      expect(tester.takeException(), isNull);
      final more = tester.getRect(moreOf('c1'));
      for (final text in ['익명', '글쓴이', '1시간 전']) {
        expect(tester.getRect(find.descendant(of: rowOf('c1'), matching: find.text(text))).right, lessThanOrEqualTo(more.left + 12), reason: text);
      }
    });

    testWidgets('댓글이 없으면 "댓글 0" 머리와 "첫 댓글을 남겨 보세요"(EmptyLine)', (tester) async {
      phone(tester);
      givenPoll(pollFixture());
      await pumpDetail(tester, 'p1');

      expect(find.text('댓글 0'), findsOneWidget);
      final empty = find.text('첫 댓글을 남겨 보세요');
      expect(empty, findsOneWidget);
      // EmptyLine 328x86: 안쪽 [32,16] 가운데, 글자 14 muted.
      final style = tester.widget<Text>(empty).style!;
      expect((style.fontSize, style.color), (14, AppColors.muted));
      expect(tester.getRect(empty).center.dx, closeTo(180, 0.5));
      final header = tester.getRect(find.text('댓글 0'));
      // 머리 아래 간격 8 뒤에 EmptyLine(위 안쪽 32 + 글자 + 아래 32 = 86).
      expect(tester.getRect(empty).top - header.bottom, closeTo(8 + 32, 1.5));
    });

    testWidgets('첫 쪽을 못 읽으면 오류와 "다시 시도" — 누르면 다시 읽는다', (tester) async {
      givenPoll(pollFixture());
      repository.commentPage = const FailureResult(NetworkFailure());
      await pumpDetail(tester, 'p1');

      expect(find.text(AppLocalizationsKo().errorNetwork), findsOneWidget);
      expect(find.text('첫 댓글을 남겨 보세요'), findsNothing);

      givenComments([commentFixture(id: 'c1', body: '다시 읽었어요')]);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('다시 읽었어요'), findsOneWidget);
      expect(find.text(AppLocalizationsKo().errorNetwork), findsNothing);
    });
  });

  group('이어 읽기(인스타처럼 — "댓글 더 보기" 버튼 없이 끝 가까이 내리면 다음 10개)', () {
    List<PollComment> page(int from, int count) => [
          for (var i = from; i < from + count; i++)
            commentFixture(id: 'c$i', body: '댓글 본문 $i', createdAt: DateTime(2026, 9, 27, 10).add(Duration(minutes: i))),
        ];

    Future<void> scrollToEnd(WidgetTester tester) async {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
    }

    testWidgets('"댓글 더 보기" 버튼은 없고, 끝까지 내리면 마지막 댓글 커서(after · after_id)로 다음 쪽을 한 번 요청한다', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 12));
      givenComments(page(1, 10), hasMore: true);
      repository.nextCommentPage = Success(PollCommentPage(comments: page(11, 2), hasMore: false));
      await pumpDetail(tester, 'p1');

      expect(find.text('댓글 더 보기'), findsNothing);
      // 처음에는 첫 쪽만 — 아직 끝 가까이 오지 않았다.
      expect(repository.commentRequests.where((r) => r.after != null), isEmpty);

      await scrollToEnd(tester);

      final more = repository.commentRequests.where((r) => r.after != null).toList();
      expect(more, hasLength(1));
      expect(more.single.afterId, 'c10');
      expect(more.single.after, DateTime(2026, 9, 27, 10).add(const Duration(minutes: 10)));
      // 이어 붙은 댓글은 목록 아래에 붙는다 — 더 내리면 보인다.
      await scrollToEnd(tester);
      expect(find.text('댓글 본문 12'), findsOneWidget);
      expect(repository.commentRequests.where((r) => r.after != null), hasLength(1));
    });

    testWidgets('has_more 가 false 면 끝까지 내려도 더 요청하지 않는다', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 10));
      givenComments(page(1, 10));
      await pumpDetail(tester, 'p1');

      await scrollToEnd(tester);
      await scrollToEnd(tester);

      expect(repository.commentRequests, hasLength(1));
    });

    testWidgets('이어 읽는 동안 목록 끝에 작은 로딩 표시가 뜨고, 겹쳐 스크롤해도 요청은 한 번이다', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 12));
      givenComments(page(1, 10), hasMore: true);
      repository.nextCommentPage = Success(PollCommentPage(comments: page(11, 2), hasMore: false));
      await pumpDetail(tester, 'p1');
      final hold = repository.holdMoreComments = Completer<void>();

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.commentRequests.where((r) => r.after != null), hasLength(1));

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('이어 읽기가 실패하면 목록 끝에 짧은 오류와 "다시 시도" — 스크롤로는 되풀이하지 않고, 누르면 이어 읽는다', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 12));
      givenComments(page(1, 10), hasMore: true);
      repository.nextCommentPage = const FailureResult(NetworkFailure());
      await pumpDetail(tester, 'p1');

      await scrollToEnd(tester);
      expect(find.text(AppLocalizationsKo().errorNetwork), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      await scrollToEnd(tester);
      expect(repository.commentRequests.where((r) => r.after != null), hasLength(1));

      repository.nextCommentPage = Success(PollCommentPage(comments: page(11, 2), hasMore: false));
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repository.commentRequests.where((r) => r.after != null), hasLength(2));
      expect(find.text('다시 시도'), findsNothing);
      await scrollToEnd(tester);
      expect(find.text('댓글 본문 12'), findsOneWidget);
    });
  });

  group('같은 글의 새 댓글 푸시(앱이 열려 있을 때)', () {
    testWidgets('알림으로 들어온 상세(피드 없음)도 쓰던 댓글 · 입력줄이 그대로고 스피너로 바뀌지 않는다', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c1', body: '먼저 온 댓글')]);
      final container = await pumpDetail(tester, 'p1', feedFirst: false);
      await tester.enterText(inputField(), '쓰던 중인 댓글');
      await tester.pump();
      final barState = tester.state(find.byType(CommentInputBar));

      // 다른 사람이 댓글을 달았다 — 서버에는 이제 댓글 2개.
      repository
        ..poll = Success(pollFixture(commentCount: 2))
        ..nextCommentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c2', aliasNo: 2, body: '새로 온 댓글')], hasMore: false));
      receivePush(container, {'route': 'poll', 'poll_id': 'p1'});
      await tester.pump();

      // 읽는 도중에도 화면이 스피너로 바뀌거나 입력줄이 내려가지 않는다.
      expect(find.byType(CommentInputBar), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();

      expect(identical(tester.state(find.byType(CommentInputBar)), barState), isTrue);
      expect(tester.widget<TextField>(inputField()).controller!.text, '쓰던 중인 댓글');
      expect(find.text('먼저 온 댓글'), findsOneWidget);
      expect(find.text('새로 온 댓글'), findsOneWidget);
      expect(find.text('댓글 2'), findsOneWidget);
    });

    testWidgets('피드를 거쳐 들어왔고 목록을 더 내려 읽은 상태여도 목록 · 스크롤 자리가 그대로고 새 댓글만 끝에 붙는다', (tester) async {
      phone(tester);
      List<PollComment> page(int from, int count) => [
            for (var i = from; i < from + count; i++)
              commentFixture(id: 'c$i', body: '댓글 본문 $i', createdAt: DateTime(2026, 9, 27, 10).add(Duration(minutes: i))),
          ];
      givenPoll(pollFixture(commentCount: 12));
      givenComments(page(1, 10), hasMore: true);
      repository.nextCommentPage = Success(PollCommentPage(comments: page(11, 2), hasMore: false));
      final container = await pumpDetail(tester, 'p1');
      // 첫 내림이 다음 쪽을 부르고, 둘째 내림이 붙은 끝까지 간다.
      for (var i = 0; i < 2; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
      }
      double offset() => tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
      final before = offset();
      expect(before, greaterThan(0));
      expect(find.text('댓글 본문 12'), findsOneWidget);

      repository
        ..poll = Success(pollFixture(commentCount: 13))
        ..nextCommentPage = Success(PollCommentPage(comments: page(13, 1), hasMore: false));
      receivePush(container, {'route': 'poll', 'poll_id': 'p1'});
      await tester.pumpAndSettle();

      // 처음 10개로 돌아가지 않았다 — 마지막으로 받은 댓글(c12) 다음부터만 읽었다.
      expect(offset(), before);
      expect(repository.commentRequests.last.afterId, 'c12');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('댓글 본문 13'), findsOneWidget);
      // 머리 숫자는 목록 맨 위에 있어 화면 밖이다 — 상태로 확인한다.
      expect(container.read(pollDetailViewModelProvider('p1')).poll?.commentCount, 13);
    });
  });

  group('입력줄(pen JgryI · Field dT2J7 · Send S64lvQ)', () {
    Finder field() => find.descendant(of: find.byType(CommentInputBar), matching: find.byType(TextField));
    Finder sendTap() => find.byKey(commentSendButtonKey);

    testWidgets('pen 값: 안내 "댓글을 남겨 주세요", 칸 280x48, 보내기 누름 영역은 44 이상(원은 40)', (tester) async {
      phone(tester);
      givenPoll(pollFixture());
      await pumpDetail(tester, 'p1');

      expect(find.text('댓글을 남겨 주세요'), findsOneWidget);
      final hint = tester.widget<TextField>(field()).decoration!.hintStyle!;
      expect((hint.fontSize, hint.color), (16, AppColors.muted));
      expect(tester.getSize(field()).width, 280);
      expect(tester.getSize(field()).height, 48);
      final send = tester.getRect(sendTap());
      expect(send.width, greaterThanOrEqualTo(44));
      expect(send.height, greaterThanOrEqualTo(44));
      // 보이는 원은 pen 처럼 40 × 40, x 304 ~ 344.
      final circle = tester.getRect(find.descendant(of: sendTap(), matching: find.byType(DecoratedBox)).first);
      expect(circle.size, const Size(40, 40));
      expect(circle.left, 304);
      // 바(80) 아래에 붙는다.
      expect(tester.getRect(find.byType(CommentInputBar)).bottom, 780);
    });

    testWidgets('글이 비면 보내기가 꺼져 있고, 글을 쓰면 켜진다', (tester) async {
      givenPoll(pollFixture());
      await pumpDetail(tester, 'p1');
      InkWell ink() => tester.widget<InkWell>(find.descendant(of: sendTap(), matching: find.byType(InkWell)));

      expect(ink().onTap, isNull);
      await tester.enterText(field(), '   ');
      await tester.pump();
      expect(ink().onTap, isNull);
      await tester.enterText(field(), '안녕');
      await tester.pump();
      expect(ink().onTap, isNotNull);
    });

    testWidgets('200자가 넘게 쓸 수 없다', (tester) async {
      givenPoll(pollFixture());
      await pumpDetail(tester, 'p1');

      await tester.enterText(field(), '가' * 250);
      await tester.pump();

      expect(tester.widget<TextField>(field()).controller!.text.runes.length, commentMaxLength);
    });

    testWidgets('보내면 앞뒤 공백을 떼어 서버로 가고, 목록 끝에 붙고, 헤더 숫자가 오르고, 칸이 비워진다', (tester) async {
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c1', body: '먼저 온 댓글')]);
      repository.addCommentResult = Success(commentFixture(id: 'c2', aliasNo: 2, body: '새 댓글', isMine: true, canDelete: true));
      await pumpDetail(tester, 'p1');

      await tester.enterText(field(), '  새 댓글 ');
      await tester.pump();
      await tester.tap(sendTap());
      await tester.pumpAndSettle();

      expect(repository.addedComments.single, (pollId: 'p1', body: '새 댓글'));
      expect(find.text('새 댓글'), findsOneWidget);
      expect(find.text('댓글 2'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      // 먼저 온 댓글 다음에 붙는다.
      expect(tester.getRect(find.text('새 댓글')).top, greaterThan(tester.getRect(find.text('먼저 온 댓글')).top));
    });

    testWidgets('하루 50개를 넘어 429 면 서버 문구를 알리고 쓴 글은 칸에 남는다', (tester) async {
      givenPoll(pollFixture(commentCount: 0));
      repository.addCommentResult = const FailureResult(RateLimitedFailure('오늘은 댓글을 더 달 수 없어요'));
      await pumpDetail(tester, 'p1');

      await tester.enterText(field(), '못 보내는 글');
      await tester.pump();
      await tester.tap(sendTap());
      await tester.pumpAndSettle();

      expect(find.text('오늘은 댓글을 더 달 수 없어요'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, '못 보내는 글');
      expect(find.text('댓글 0'), findsOneWidget);
    });

    testWidgets('글이 사라졌으면(404) 서버 문구를 알리고 쓴 글은 칸에 남는다', (tester) async {
      givenPoll(pollFixture());
      repository.addCommentResult = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'));
      await pumpDetail(tester, 'p1');

      await tester.enterText(field(), '내 글');
      await tester.pump();
      await tester.tap(sendTap());
      await tester.pumpAndSettle();

      expect(find.text('질문을 찾을 수 없어요'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, '내 글');
    });

    testWidgets('채팅 입력줄(1,000자)을 쓰지 않는다 — 댓글은 200자 · 안내 · 누름 영역이 다르다', (tester) async {
      givenPoll(pollFixture());
      await pumpDetail(tester, 'p1');
      expect(find.byType(ChatInputBar), findsNothing);
    });
  });

  group('"…" 메뉴(pen tWng7 · ptEjj · Li2Hx)', () {
    Finder sheetText(String text) => find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

    testWidgets('내 댓글 — 삭제하기 · 취소 (tWng7), 신고는 없다', (tester) async {
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c1', isMine: true, canDelete: true)]);
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c1'));
      await tester.pumpAndSettle();

      expect(sheetText('삭제하기'), findsOneWidget);
      expect(sheetText('취소'), findsOneWidget);
      expect(sheetText('신고하기'), findsNothing);
      // 행 52 · 삭제 글자는 error.
      expect(tester.getSize(find.ancestor(of: sheetText('삭제하기'), matching: find.byType(InkWell)).first).height, 52);
      expect(tester.widget<Text>(sheetText('삭제하기')).style!.color, AppColors.error);
    });

    testWidgets('내 글에 달린 남의 댓글 — 삭제하기 · 신고하기 · 취소 (ptEjj)', (tester) async {
      givenPoll(pollFixture(isMine: true, commentCount: 1));
      givenComments([commentFixture(id: 'c1', canDelete: true)]);
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c1'));
      await tester.pumpAndSettle();

      expect(sheetText('삭제하기'), findsOneWidget);
      expect(sheetText('신고하기'), findsOneWidget);
      expect(sheetText('취소'), findsOneWidget);
      // 삭제 → 신고 → (구분선) → 취소 순서.
      expect(tester.getRect(sheetText('삭제하기')).top, lessThan(tester.getRect(sheetText('신고하기')).top));
      expect(tester.getRect(sheetText('신고하기')).top, lessThan(tester.getRect(sheetText('취소')).top));
      // 신고 줄은 Li2Hx 서식(Pretendard 16 ink / 3D 사이렌 22), 삭제 줄은 pen 18b · 18c 대로 lucide trash-2 20 error(글 메뉴 15d-1 과 같다).
      expect(tester.widget<Text>(sheetText('신고하기')).style!.color, AppColors.ink);
      final icons = tester.widgetList<Icon3d>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Icon3d)));
      expect(icons.map((i) => (i.icon, i.size)), [(AppIcon3d.siren, 22.0)]);
      final trash = tester.widget<Icon>(find.descendant(of: find.byType(BottomSheet), matching: find.byIcon(AppIcons.trash2)));
      expect((trash.size, trash.color), (20.0, AppColors.error));
    });

    testWidgets('그 밖의 남의 댓글 — 신고하기 · 취소 (Li2Hx), 삭제는 없다', (tester) async {
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c1')]);
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c1'));
      await tester.pumpAndSettle();

      expect(sheetText('신고하기'), findsOneWidget);
      expect(sheetText('취소'), findsOneWidget);
      expect(sheetText('삭제하기'), findsNothing);
    });

    testWidgets('취소를 누르면 아무 일 없이 닫힌다', (tester) async {
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c1')]);
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c1'));
      await tester.pumpAndSettle();
      await tester.tap(sheetText('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(repository.deletedComments, isEmpty);
      expect(safety.reports, isEmpty);
    });

    testWidgets('신고하기 → 신고 시트 → 사유를 고르고 보내면 poll_comment 대상으로 가고 댓글은 남는다', (tester) async {
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c3', body: '신고할 댓글')]);
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c3'));
      await tester.pumpAndSettle();
      await tester.tap(sheetText('신고하기'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportSheet), findsOneWidget);
      await tester.tap(find.text('광고·스팸'));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(ReportSheet), matching: find.text('신고하기')));
      await tester.pumpAndSettle();

      expect(safety.reports.single.target, {'target_type': 'poll_comment', 'target_id': 'c3'});
      expect(safety.reports.single.reason, ReportReason.spam);
      expect(find.text('신고했어요. 운영팀이 확인할게요'), findsOneWidget);
      expect(find.text('신고할 댓글'), findsOneWidget);
    });

    testWidgets('댓글 신고 완료 토스트는 입력칸과 겹치지 않고 입력줄 위에 뜬다 (360×780)', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c3')]);
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c3'));
      await tester.pumpAndSettle();
      await tester.tap(sheetText('신고하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('광고·스팸'));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(ReportSheet), matching: find.text('신고하기')));
      await tester.pumpAndSettle();

      final toast = tester.getRect(find.byType(AppToast));
      final input = tester.getRect(find.descendant(of: find.byType(CommentInputBar), matching: find.byType(TextField)));
      expect(toast.bottom, lessThanOrEqualTo(tester.getRect(find.byType(CommentInputBar)).top));
      expect(toast.overlaps(input), isFalse);
    });

    testWidgets('토스트가 떠 있는 동안에도 입력칸을 눌러 포커스를 줄 수 있다 — 투명한 토스트 영역이 탭을 먹지 않는다', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c3')]);
      await pumpDetail(tester, 'p1');
      await reportCommentThrough(tester, 'c3');
      expect(find.byType(AppToast), findsOneWidget);

      await tester.tap(inputField());
      await tester.pump();

      final editable = tester.widget<EditableText>(find.descendant(of: inputField(), matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('입력이 4줄로 자라 입력줄이 80 보다 커져도 토스트는 입력칸과 겹치지 않는다', (tester) async {
      phone(tester);
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c3')]);
      await pumpDetail(tester, 'p1');
      await tester.enterText(inputField(), '가\n나\n다\n라');
      await tester.pump();
      expect(tester.getSize(find.byType(CommentInputBar)).height, greaterThan(commentInputBarHeight));

      await reportCommentThrough(tester, 'c3');

      final toast = tester.getRect(find.byType(AppToast));
      expect(toast.overlaps(tester.getRect(inputField())), isFalse);
      expect(toast.bottom, lessThanOrEqualTo(tester.getRect(find.byType(CommentInputBar)).top));
    });

    testWidgets('4줄을 쓰고 보내기에 실패해도 실패 토스트가 입력칸과 겹치지 않는다 (보낼 때 비워졌던 칸이 되돌아온 뒤의 높이로 올린다)', (tester) async {
      phone(tester);
      givenPoll(pollFixture());
      final hold = repository.holdAddComment = Completer<void>();
      repository.addCommentResult = const FailureResult(RateLimitedFailure('오늘은 댓글을 더 달 수 없어요'));
      await pumpDetail(tester, 'p1');
      await tester.enterText(inputField(), '가\n나\n다\n라');
      await tester.pump();

      await tester.tap(find.byKey(commentSendButtonKey));
      // 보내는 동안 칸이 비워져 입력줄이 한 줄 높이로 줄어든 모습이 한 프레임 그려진다(실제 네트워크 응답은 프레임 뒤에 온다).
      await tester.pump();
      expect(tester.getSize(find.byType(CommentInputBar)).height, commentInputBarHeight);
      hold.complete();
      await tester.pumpAndSettle();

      expect(find.text('오늘은 댓글을 더 달 수 없어요'), findsOneWidget);
      expect(tester.widget<TextField>(inputField()).controller!.text, '가\n나\n다\n라');
      final toast = tester.getRect(find.byType(AppToast));
      expect(toast.overlaps(tester.getRect(inputField())), isFalse);
      expect(toast.bottom, lessThanOrEqualTo(tester.getRect(find.byType(CommentInputBar)).top));
    });

    testWidgets('아래 안전 영역(iOS 홈 바 34)이 있어도 토스트는 입력줄 바로 위에 뜬다 — Scaffold 가 이미 올린 만큼을 또 더하지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c3')]);
      await pumpDetail(tester, 'p1');
      expect(tester.getSize(find.byType(CommentInputBar)).height, 80 + 34);

      await reportCommentThrough(tester, 'c3');

      final bar = tester.getRect(find.byType(CommentInputBar));
      final toast = tester.getRect(find.byType(AppToast));
      expect(toast.overlaps(tester.getRect(inputField())), isFalse);
      // 입력줄 바로 위(토스트 아래 여백 10) — 34 가 두 번 더해지면 44 떠 있다.
      expect(bar.top - toast.bottom, closeTo(10, 1));
    });

    testWidgets('글 신고 완료 토스트도 입력줄 위에 뜬다', (tester) async {
      phone(tester);
      givenPoll(pollFixture());
      await pumpDetail(tester, 'p1');

      final siren = find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.siren);
      await tester.tap(find.ancestor(of: siren, matching: find.byType(InkResponse)).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('광고·스팸'));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(ReportSheet), matching: find.text('신고하기')));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(AppToast)).bottom, lessThanOrEqualTo(tester.getRect(find.byType(CommentInputBar)).top));
    });

    testWidgets('삭제하기 → 확인 시트(NF999) → 삭제하기를 누르면 목록에서 빠지고 헤더 숫자가 내려간다', (tester) async {
      givenPoll(pollFixture(commentCount: 2));
      givenComments([
        commentFixture(id: 'c1', body: '지울 댓글', isMine: true, canDelete: true),
        commentFixture(id: 'c2', body: '남을 댓글'),
      ]);
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c1'));
      await tester.pumpAndSettle();
      await tester.tap(sheetText('삭제하기'));
      await tester.pumpAndSettle();

      expect(find.text('댓글을 삭제할까요?'), findsOneWidget);
      expect(find.text('삭제한 댓글은 되돌릴 수 없어요.'), findsOneWidget);
      expect(repository.deletedComments, isEmpty);

      await tester.tap(find.widgetWithText(AppButton, '삭제하기'));
      await tester.pumpAndSettle();

      expect(repository.deletedComments, ['c1']);
      expect(find.text('지울 댓글'), findsNothing);
      expect(find.text('남을 댓글'), findsOneWidget);
      expect(find.text('댓글 1'), findsOneWidget);
      expect(find.text('삭제했어요'), findsOneWidget);
    });

    testWidgets('확인 시트에서 취소하면 지우지 않는다', (tester) async {
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c1', isMine: true, canDelete: true)]);
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c1'));
      await tester.pumpAndSettle();
      await tester.tap(sheetText('삭제하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, '취소'));
      await tester.pumpAndSettle();

      expect(repository.deletedComments, isEmpty);
      expect(find.text('댓글 1'), findsOneWidget);
    });

    testWidgets('삭제가 실패하면 목록은 그대로고 이유를 토스트로 알린다', (tester) async {
      givenPoll(pollFixture(commentCount: 1));
      givenComments([commentFixture(id: 'c1', body: '그대로', isMine: true, canDelete: true)]);
      repository.deleteCommentResult = const FailureResult(NetworkFailure());
      await pumpDetail(tester, 'p1');

      await tester.tap(moreOf('c1'));
      await tester.pumpAndSettle();
      await tester.tap(sheetText('삭제하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, '삭제하기'));
      await tester.pumpAndSettle();

      expect(find.text('그대로'), findsOneWidget);
      expect(find.text(AppLocalizationsKo().errorNetwork), findsOneWidget);
    });
  });

  testWidgets('낭독기는 "…" 를 48 크기의 "더보기" 버튼으로 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    givenPoll(pollFixture(commentCount: 1));
    givenComments([commentFixture(id: 'c1')]);
    await pumpDetail(tester, 'p1');

    expect(
      tester.getSemantics(moreOf('c1')),
      matchesSemantics(tooltip: '더보기', isButton: true, hasTapAction: true, isEnabled: true, hasEnabledState: true, isFocusable: true, hasFocusAction: true),
    );
    expect(tester.renderObject<RenderBox>(moreOf('c1')).size, const Size(48, 48));
    handle.dispose();
  });
}
