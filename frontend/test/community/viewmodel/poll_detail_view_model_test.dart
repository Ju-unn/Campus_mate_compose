import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/model/data/poll_feed.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/community/viewmodel/poll_detail_view_model.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/analytics/fake_analytics_service.dart';
import '../model/repository/fake_community_repository.dart';

void main() {
  late FakeCommunityRepository repository;

  setUp(() => repository = FakeCommunityRepository());

  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [
        communityRepositoryProvider.overrideWithValue(repository),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 상세를 열고 첫 응답(글 · 댓글)이 반영될 때까지 기다린다.
  Future<ProviderContainer> open({bool feedFirst = false, String pollId = 'p1'}) async {
    final container = newContainer();
    if (feedFirst) {
      container.read(communityFeedViewModelProvider);
      await container.read(communityFeedViewModelProvider.notifier).refresh();
    }
    container.listen(pollDetailViewModelProvider(pollId), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  PollDetailViewModel viewModel(ProviderContainer c) => c.read(pollDetailViewModelProvider('p1').notifier);

  test('피드에 있는 글이면 처음부터 그 값을 쓰고, 댓글 첫 쪽을 읽는다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture(commentCount: 12)], hasMore: false))
      ..poll = Success(pollFixture(commentCount: 12))
      ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1'), commentFixture(id: 'c2')], hasMore: true));
    final container = newContainer();
    container.read(communityFeedViewModelProvider);
    await container.read(communityFeedViewModelProvider.notifier).refresh();

    container.listen(pollDetailViewModelProvider('p1'), (_, _) {});
    // 첫 프레임부터 피드 값 — 깜박임 없이 카드가 보인다.
    final initial = container.read(pollDetailViewModelProvider('p1'));
    expect(initial.poll?.id, 'p1');
    expect(initial.isLoadingPoll, isFalse);
    expect(initial.isLoadingComments, isTrue);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final loaded = container.read(pollDetailViewModelProvider('p1'));
    expect(loaded.comments.map((c) => c.id), ['c1', 'c2']);
    expect(loaded.hasMoreComments, isTrue);
    expect(loaded.isLoadingComments, isFalse);
    expect(repository.commentRequests.single.after, isNull);
  });

  test('알림에서 바로 들어오면(피드 없음) pollId 로 fetchPoll 해서 글을 채운다', () async {
    repository
      ..poll = Success(pollFixture(commentCount: 2))
      ..commentPage = Success(PollCommentPage(comments: [commentFixture()], hasMore: false));
    final container = await open();

    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(repository.fetchedPollIds, ['p1']);
    expect(s.poll?.commentCount, 2);
    expect(s.isLoadingPoll, isFalse);
    expect(s.pollError, isNull);
    // 피드를 일부러 만들지 않는다 — 알림 한 번에 피드 전체를 읽지 않는다.
    expect(container.exists(communityFeedViewModelProvider), isFalse);
  });

  test('글이 없으면(404) 글 오류를 둔다', () async {
    repository.poll = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'));
    repository.commentPage = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'));
    final container = await open();

    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(s.poll, isNull);
    expect(s.pollError, isA<ServerRejectedFailure>());
  });

  test('더 보기는 마지막으로 받은 댓글의 시각 · id 를 커서로 보내고 뒤에 붙인다', () async {
    final at = DateTime.utc(2026, 11, 10, 5);
    repository
      ..poll = Success(pollFixture())
      ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1', createdAt: at)], hasMore: true))
      ..nextCommentPage = Success(PollCommentPage(
        comments: [commentFixture(id: 'c2', createdAt: at.add(const Duration(minutes: 1)))],
        hasMore: false,
      ));
    final container = await open();

    await viewModel(container).loadMore();

    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(s.comments.map((c) => c.id), ['c1', 'c2']);
    expect(s.hasMoreComments, isFalse);
    expect(repository.commentRequests.last.after, at);
    expect(repository.commentRequests.last.afterId, 'c1');
  });

  test('이어 읽기가 겹쳐 불려도 요청은 한 번만 나간다', () async {
    repository
      ..poll = Success(pollFixture())
      ..commentPage = Success(PollCommentPage(comments: [commentFixture()], hasMore: true))
      ..nextCommentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c2')], hasMore: false));
    final container = await open();

    final first = viewModel(container).loadMore();
    final second = viewModel(container).loadMore();
    await Future.wait([first, second]);

    expect(repository.commentRequests.where((r) => r.after != null), hasLength(1));
  });

  test('더 없으면(has_more false) 이어 읽지 않는다', () async {
    repository
      ..poll = Success(pollFixture())
      ..commentPage = Success(PollCommentPage(comments: [commentFixture()], hasMore: false));
    final container = await open();

    await viewModel(container).loadMore();

    expect(repository.commentRequests.where((r) => r.after != null), isEmpty);
  });

  test('이어 읽기가 실패하면 목록은 그대로 두고 오류를 남기며, 그동안은 자동으로 다시 부르지 않는다', () async {
    repository
      ..poll = Success(pollFixture())
      ..commentPage = Success(PollCommentPage(comments: [commentFixture()], hasMore: true))
      ..nextCommentPage = const FailureResult(NetworkFailure());
    final container = await open();

    await viewModel(container).loadMore();

    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(s.comments, hasLength(1));
    expect(s.hasMoreComments, isTrue);
    expect(s.isLoadingMoreComments, isFalse);
    expect(s.moreError, isA<NetworkFailure>());

    await viewModel(container).loadMore();
    expect(repository.commentRequests.where((r) => r.after != null), hasLength(1));
  });

  test('다시 시도는 오류를 지우고 같은 자리부터 다시 읽는다', () async {
    repository
      ..poll = Success(pollFixture())
      ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1')], hasMore: true))
      ..nextCommentPage = const FailureResult(NetworkFailure());
    final container = await open();
    await viewModel(container).loadMore();

    repository.nextCommentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c2')], hasMore: false));
    await viewModel(container).retryLoadMore();

    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(s.moreError, isNull);
    expect(s.comments.map((c) => c.id), ['c1', 'c2']);
    expect(repository.commentRequests.last.afterId, 'c1');
  });

  test('보내면 앞뒤 공백을 뗀 글을 목록 끝에 붙이고 댓글 수를 올린다(피드 카드 수도 같이)', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture(commentCount: 1)], hasMore: false))
      ..poll = Success(pollFixture(commentCount: 1))
      ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1')], hasMore: false))
      ..addCommentResult = Success(commentFixture(id: 'c2', body: '안녕', isMine: true, canDelete: true));
    final container = await open(feedFirst: true);

    final failure = await viewModel(container).send('  안녕\n ');

    expect(failure, isNull);
    expect(repository.addedComments.single, (pollId: 'p1', body: '안녕'));
    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(s.comments.map((c) => c.id), ['c1', 'c2']);
    expect(s.poll?.commentCount, 2);
    expect(s.isSending, isFalse);
    expect(container.read(communityFeedViewModelProvider).polls.single.commentCount, 2);
  });

  test('공백만 있으면 보내지 않는다', () async {
    repository.poll = Success(pollFixture());
    final container = await open();

    await viewModel(container).send('   ');

    expect(repository.addedComments, isEmpty);
  });

  test('보내는 동안 다시 보내도 한 번만 간다', () async {
    repository
      ..poll = Success(pollFixture())
      ..holdAddComment = Completer<void>()
      ..addCommentResult = Success(commentFixture(id: 'c2'));
    final container = await open();

    final first = viewModel(container).send('하나');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(pollDetailViewModelProvider('p1')).isSending, isTrue);
    final second = await viewModel(container).send('둘');
    repository.holdAddComment!.complete();
    await first;

    expect(second, isNull);
    expect(repository.addedComments, hasLength(1));
  });

  test('하루 한도(429)로 막히면 목록 · 수를 건드리지 않고 이유를 돌려준다', () async {
    repository
      ..poll = Success(pollFixture(commentCount: 3))
      ..addCommentResult = const FailureResult(RateLimitedFailure('오늘은 댓글을 더 달 수 없어요'));
    final container = await open();

    final failure = await viewModel(container).send('안녕');

    expect(failure, isA<RateLimitedFailure>());
    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(s.comments, isEmpty);
    expect(s.poll?.commentCount, 3);
    expect(s.isSending, isFalse);
  });

  test('더 보기가 남은 채 보낸 댓글이 있어도 커서는 서버에서 받은 마지막 줄이라 사이 댓글을 건너뛰지 않는다', () async {
    final at = DateTime.utc(2026, 11, 10, 5);
    repository
      ..poll = Success(pollFixture(commentCount: 3))
      ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1', createdAt: at)], hasMore: true))
      ..addCommentResult = Success(commentFixture(id: 'c9', createdAt: at.add(const Duration(minutes: 9)), isMine: true))
      ..nextCommentPage = Success(PollCommentPage(
        comments: [
          commentFixture(id: 'c2', createdAt: at.add(const Duration(minutes: 1))),
          commentFixture(id: 'c9', createdAt: at.add(const Duration(minutes: 9)), isMine: true),
        ],
        hasMore: false,
      ));
    final container = await open();

    await viewModel(container).send('내 댓글');
    await viewModel(container).loadMore();

    expect(repository.commentRequests.last.afterId, 'c1');
    // 같은 댓글이 두 번 들어오지 않고, 시간 순서가 맞는다.
    expect(container.read(pollDetailViewModelProvider('p1')).comments.map((c) => c.id), ['c1', 'c2', 'c9']);
  });

  test('삭제하면 목록에서 빼고 수를 내린다', () async {
    repository
      ..poll = Success(pollFixture(commentCount: 2))
      ..commentPage = Success(PollCommentPage(
        comments: [commentFixture(id: 'c1', canDelete: true), commentFixture(id: 'c2')],
        hasMore: false,
      ));
    final container = await open();

    final failure = await viewModel(container).deleteComment('c1');

    expect(failure, isNull);
    expect(repository.deletedComments, ['c1']);
    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(s.comments.map((c) => c.id), ['c2']);
    expect(s.poll?.commentCount, 1);
  });

  test('삭제가 연결 실패면 그대로 두고, 서버가 없다고 하면(이미 지워짐) 목록에서만 뺀다', () async {
    repository
      ..poll = Success(pollFixture(commentCount: 2))
      ..commentPage = Success(PollCommentPage(
        comments: [commentFixture(id: 'c1', canDelete: true), commentFixture(id: 'c2', canDelete: true)],
        hasMore: false,
      ))
      ..deleteCommentResult = const FailureResult(NetworkFailure());
    final container = await open();

    expect(await viewModel(container).deleteComment('c1'), isA<NetworkFailure>());
    expect(container.read(pollDetailViewModelProvider('p1')).comments, hasLength(2));

    repository.deleteCommentResult = const FailureResult(ServerRejectedFailure('댓글을 찾을 수 없어요'));
    expect(await viewModel(container).deleteComment('c2'), isA<ServerRejectedFailure>());
    expect(container.read(pollDetailViewModelProvider('p1')).comments.map((c) => c.id), ['c1']);
  });

  test('투표는 피드 뷰모델에 맡기고, 피드에 없던 글은 다시 읽어 맞춘다', () async {
    repository
      ..poll = Success(pollFixture(commentCount: 4))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a, commentCount: 4), rewarded: false));
    final container = await open();
    repository.poll = Success(pollFixture(myChoice: PollChoice.a, commentCount: 4));

    final notice = await viewModel(container).vote(PollChoice.a);

    expect(notice, isNull);
    expect(repository.votes.single.choice, PollChoice.a);
    expect(container.read(pollDetailViewModelProvider('p1')).poll?.myChoice, PollChoice.a);
    expect(container.read(pollDetailViewModelProvider('p1')).isVoting, isFalse);
  });

  group('새 댓글 푸시 — refreshForNewComment', () {
    test('글 값은 그대로 두고 숫자만 맞추며, 끝까지 읽은 목록 뒤에 새 댓글만 붙인다 (마지막으로 받은 줄 다음부터)', () async {
      repository
        ..poll = Success(pollFixture(commentCount: 1))
        ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1')], hasMore: false));
      final container = await open();
      final loadingFlags = <bool>[];
      container.listen(pollDetailViewModelProvider('p1'), (_, next) => loadingFlags.add(next.poll == null || next.isLoadingComments));
      repository
        ..poll = Success(pollFixture(commentCount: 2))
        ..nextCommentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c2')], hasMore: false));

      await viewModel(container).refreshForNewComment();

      final s = container.read(pollDetailViewModelProvider('p1'));
      expect(s.comments.map((c) => c.id), ['c1', 'c2']);
      expect(s.poll?.commentCount, 2);
      expect(s.isLoadingPoll, isFalse);
      expect(repository.commentRequests.last.afterId, 'c1');
      // 읽는 동안 글이 비거나 목록이 로딩 상태로 돌아간 적이 없다.
      expect(loadingFlags, everyElement(isFalse));
    });

    test('더 읽을 댓글이 남아 있으면 목록은 그대로 두고(스크롤 때 이어 읽는다) 숫자만 맞춘다', () async {
      repository
        ..poll = Success(pollFixture(commentCount: 20))
        ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1')], hasMore: true));
      final container = await open();
      repository.poll = Success(pollFixture(commentCount: 21));

      await viewModel(container).refreshForNewComment();

      final s = container.read(pollDetailViewModelProvider('p1'));
      expect(s.comments.map((c) => c.id), ['c1']);
      expect(s.hasMoreComments, isTrue);
      expect(s.poll?.commentCount, 21);
      expect(repository.commentRequests.where((r) => r.after != null), isEmpty);
    });

    test('푸시로 이미 받아 둔 내 댓글이 보내기 응답으로 또 들어오지 않고, 숫자도 한 번만 오른다 (푸시 붙이기 → 보내기 응답 순서)', () async {
      final t0 = DateTime.utc(2026, 11, 10, 5);
      repository
        ..poll = Success(pollFixture(commentCount: 1))
        ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1', createdAt: t0)], hasMore: false))
        ..holdAddComment = Completer<void>()
        ..addCommentResult = Success(commentFixture(id: 'mine', isMine: true, canDelete: true, createdAt: t0.add(const Duration(minutes: 2))));
      final container = await open();

      final sending = viewModel(container).send('내 댓글');
      await Future<void>.delayed(Duration.zero);
      // 서버는 이미 내 댓글을 저장했다 — 푸시가 먼저 와서 남의 댓글과 내 댓글을 같이 읽어 온다. 서버 숫자는 3.
      repository
        ..poll = Success(pollFixture(commentCount: 3))
        ..nextCommentPage = Success(PollCommentPage(
          comments: [
            commentFixture(id: 'other', createdAt: t0.add(const Duration(minutes: 1))),
            commentFixture(id: 'mine', isMine: true, canDelete: true, createdAt: t0.add(const Duration(minutes: 2))),
          ],
          hasMore: false,
        ));
      await viewModel(container).refreshForNewComment();
      expect(container.read(pollDetailViewModelProvider('p1')).comments.map((c) => c.id), ['c1', 'other', 'mine']);

      repository.holdAddComment!.complete();
      expect(await sending, isNull);

      final s = container.read(pollDetailViewModelProvider('p1'));
      expect(s.comments.map((c) => c.id), ['c1', 'other', 'mine']);
      expect(s.poll?.commentCount, 3);
    });

    test('이어 읽는 중에 온 푸시는 버리지 않는다 — 읽기가 끝난 뒤 새 댓글을 한 번 더 읽는다', () async {
      final t0 = DateTime.utc(2026, 11, 10, 5);
      repository
        ..poll = Success(pollFixture(commentCount: 2))
        ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1', createdAt: t0)], hasMore: true))
        ..nextCommentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c2', createdAt: t0.add(const Duration(minutes: 1)))], hasMore: false))
        ..holdMoreComments = Completer<void>();
      final container = await open();

      final loading = viewModel(container).loadMore();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pollDetailViewModelProvider('p1')).isLoadingMoreComments, isTrue);
      await viewModel(container).refreshForNewComment();
      // 읽는 중에는 겹쳐 보내지 않는다.
      expect(repository.commentRequests.where((r) => r.after != null), hasLength(1));

      repository.holdMoreComments!.complete();
      await loading;
      await pumpEventQueue();

      // 끝난 뒤 마지막으로 받은 줄(c2) 다음부터 한 번 더 읽었다.
      final more = repository.commentRequests.where((r) => r.after != null).toList();
      expect(more, hasLength(2));
      expect(more.last.afterId, 'c2');
    });

    test('푸시가 없었으면 이어 읽기가 끝나도 더 읽지 않는다', () async {
      repository
        ..poll = Success(pollFixture(commentCount: 2))
        ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1')], hasMore: true))
        ..nextCommentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c2')], hasMore: false));
      final container = await open();

      await viewModel(container).loadMore();
      await pumpEventQueue();

      expect(repository.commentRequests.where((r) => r.after != null), hasLength(1));
    });

    test('읽기에 실패해도 조용하다 — 목록 · 글은 그대로고 오류를 띄우지 않는다', () async {
      repository
        ..poll = Success(pollFixture(commentCount: 1))
        ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1')], hasMore: false));
      final container = await open();
      repository
        ..poll = const FailureResult(NetworkFailure())
        ..nextCommentPage = const FailureResult(NetworkFailure());

      await viewModel(container).refreshForNewComment();

      final s = container.read(pollDetailViewModelProvider('p1'));
      expect(s.comments.map((c) => c.id), ['c1']);
      expect(s.poll?.commentCount, 1);
      expect((s.commentsError, s.moreError, s.pollError), (null, null, null));
    });
  });

  test('다시 시도는 실패한 댓글 첫 쪽을 다시 읽는다', () async {
    repository
      ..poll = Success(pollFixture())
      ..commentPage = const FailureResult(NetworkFailure());
    final container = await open();
    expect(container.read(pollDetailViewModelProvider('p1')).commentsError, isA<NetworkFailure>());

    repository.commentPage = Success(PollCommentPage(comments: [commentFixture()], hasMore: false));
    await viewModel(container).refresh();

    final s = container.read(pollDetailViewModelProvider('p1'));
    expect(s.commentsError, isNull);
    expect(s.comments, hasLength(1));
  });

  group('아래로 당겨 새로 고침 — refresh', () {
    Future<ProviderContainer> openWith(List<PollComment> comments, {int commentCount = 1}) {
      repository
        ..poll = Success(pollFixture(commentCount: commentCount))
        ..commentPage = Success(PollCommentPage(comments: comments, hasMore: false));
      return open();
    }

    int firstPageRequests() => repository.commentRequests.where((r) => r.after == null).length;

    test('실패한 게 없어도 글과 댓글 첫 쪽을 다시 읽어 갈아 끼운다', () async {
      final container = await openWith([commentFixture(id: 'c1')]);
      repository
        ..poll = Success(pollFixture(commentCount: 2))
        ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1'), commentFixture(id: 'c2')], hasMore: true));

      await viewModel(container).refresh();

      expect(repository.fetchedPollIds, ['p1', 'p1']);
      expect(firstPageRequests(), 2);
      final s = container.read(pollDetailViewModelProvider('p1'));
      expect(s.poll?.commentCount, 2);
      expect(s.comments.map((c) => c.id), ['c1', 'c2']);
      expect(s.hasMoreComments, isTrue);
      expect(s.isLoadingComments, isFalse);
    });

    test('읽는 동안 보이던 댓글을 비우지 않는다', () async {
      final container = await openWith([commentFixture(id: 'c1')]);
      final hold = repository.holdFirstComments = Completer<void>();

      final refreshing = viewModel(container).refresh();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pollDetailViewModelProvider('p1')).comments.map((c) => c.id), ['c1']);

      hold.complete();
      await refreshing;
    });

    test('실패하면 보이던 댓글은 그대로 두고 오류를 띄우지 않는다 — 글 다시 읽기 실패와 같다', () async {
      final container = await openWith([commentFixture(id: 'c1')]);
      repository
        ..poll = const FailureResult(NetworkFailure())
        ..commentPage = const FailureResult(NetworkFailure());

      await viewModel(container).refresh();

      expect(firstPageRequests(), 2);
      final s = container.read(pollDetailViewModelProvider('p1'));
      expect(s.comments.map((c) => c.id), ['c1']);
      expect(s.poll?.commentCount, 1);
      expect((s.commentsError, s.moreError, s.pollError), (null, null, null));
      expect(s.isLoadingComments, isFalse);
    });

    test('읽는 사이 보낸 댓글은 받은 첫 쪽에 아직 없어도 목록에 남는다', () async {
      final container = await openWith([commentFixture(id: 'c1')]);
      final hold = repository.holdFirstComments = Completer<void>();
      final refreshing = viewModel(container).refresh();

      repository.addCommentResult = Success(commentFixture(id: 'c9', createdAt: DateTime(2026, 9, 27, 13, 30), isMine: true));
      expect(await viewModel(container).send('방금 쓴 댓글'), isNull);
      hold.complete();
      await refreshing;

      final s = container.read(pollDetailViewModelProvider('p1'));
      expect(s.comments.map((c) => c.id), ['c1', 'c9']);
      expect(s.isSending, isFalse);
    });

    test('끝의 이어 읽기 오류가 떠 있었어도 새로 고침이 되면 지운다 — 첫 쪽부터 다시 이어 읽는다', () async {
      repository
        ..poll = Success(pollFixture(commentCount: 12))
        ..commentPage = Success(PollCommentPage(comments: [commentFixture(id: 'c1')], hasMore: true))
        ..nextCommentPage = const FailureResult(NetworkFailure());
      final container = await open();
      await viewModel(container).loadMore();
      expect(container.read(pollDetailViewModelProvider('p1')).moreError, isA<NetworkFailure>());

      await viewModel(container).refresh();

      final s = container.read(pollDetailViewModelProvider('p1'));
      expect(s.moreError, isNull);
      expect(s.hasMoreComments, isTrue);
    });
  });
}

