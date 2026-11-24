import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/me/model/repository/me_repository_provider.dart';
import 'package:campus_mate/me/model/data/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/data/feed_page.dart';

import '../../me/model/repository/fake_me_repository.dart';
import '../../core/analytics/fake_analytics_service.dart';
import '../model/repository/fake_community_repository.dart';

/// 이름 · 학교는 지어낸 값이다.
const _profile = MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: null,
  heightCm: null,
  mbti: null,
  avatarUrl: null,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: null,
  preferredHeightMax: null,
  bio: '',
  heartBalance: 320,
);

void main() {
  late FakeCommunityRepository repository;
  late FakeAnalyticsService analytics;

  Future<ProviderContainer> start() async {
    final container = ProviderContainer(
      overrides: [
        communityRepositoryProvider.overrideWithValue(repository),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(container.dispose);
    container.read(communityFeedViewModelProvider);
    await container.read(communityFeedViewModelProvider.notifier).refresh();
    return container;
  }

  CommunityFeedViewModel viewModel(ProviderContainer c) => c.read(communityFeedViewModelProvider.notifier);

  setUp(() {
    repository = FakeCommunityRepository();
    analytics = FakeAnalyticsService();
  });

  test('열면 첫 쪽을 읽는다', () async {
    repository.page = Success(FeedPage(items: [itemFixture()], hasMore: true));
    final container = await start();
    final state = container.read(communityFeedViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.items.single.id, 'p1');
    expect(state.hasMore, isTrue);
  });

  test('첫 쪽이 실패하면 문구를 둔다', () async {
    repository.page = const FailureResult(NetworkFailure());
    final container = await start();
    expect(container.read(communityFeedViewModelProvider).error, isA<NetworkFailure>());
  });

  test('더 내리면 맨 아래 글의 시각과 id 를 커서로 보내고 뒤에 붙인다(겹친 글은 거른다)', () async {
    final last = itemFixture(id: 'p2', createdAt: DateTime(2026, 9, 27, 13));
    repository
      ..page = Success(FeedPage(items: [itemFixture(), last], hasMore: true))
      ..nextPage = Success(FeedPage(items: [last, itemFixture(id: 'p3')], hasMore: false));
    final container = await start();

    await viewModel(container).loadMore();

    expect(repository.pageRequests.last, (tab: CommunityFeedTab.all, before: last.createdAt, beforeId: 'p2'));
    expect(container.read(communityFeedViewModelProvider).items.map((p) => p.id), ['p1', 'p2', 'p3']);
    expect(container.read(communityFeedViewModelProvider).hasMore, isFalse);
  });

  test('더 없으면 요청하지 않는다', () async {
    repository.page = Success(FeedPage(items: [itemFixture()], hasMore: false));
    final container = await start();
    await viewModel(container).loadMore();
    expect(repository.pageRequests, hasLength(1));
  });

  test('투표하면 그 글을 서버 값으로 바꾸고, 보상이면 하트를 받았다는 알림을 준다', () async {
    repository
      ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(aCount: 6, myChoice: PollChoice.a), rewarded: true));
    final container = await start();

    final notice = await viewModel(container).vote('p1', PollChoice.a);

    expect(notice?.isReward, isTrue); // 하루 첫 투표 5하트(2026-10-16 사용자 확정, 종전 10) — 글자는 화면이 ARB 에서 읽는다
    expect(container.read(communityFeedViewModelProvider).items.single.poll!.myChoice, PollChoice.a);
  });

  test('보상이 없으면 토스트도 없다', () async {
    repository
      ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.b), rewarded: false));
    final container = await start();
    expect(await viewModel(container).vote('p1', PollChoice.b), isNull);
  });

  group('보유 하트(내 프로필) — 홈 칩 · 하트 스토어 · 설정이 같은 값을 읽는다', () {
    late FakeMeRepository me;

    /// 화면이 이미 잔액을 한 번 읽은 상태에서 시작한다.
    Future<ProviderContainer> startWithProfile() async {
      me = FakeMeRepository(const Success(_profile));
      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repository),
          meRepositoryProvider.overrideWithValue(me),
        ],
      );
      addTearDown(container.dispose);
      await container.read(myProfileProvider.future);
      await container.read(communityFeedViewModelProvider.notifier).refresh();
      return container;
    }

    test('투표로 하트를 받으면 내 프로필을 다시 읽는다 — 상점 · 홈의 잔액이 바로 맞는다', () async {
      repository
        ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
        ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: true));
      final container = await startWithProfile();

      await viewModel(container).vote('p1', PollChoice.a);
      await container.read(myProfileProvider.future);

      expect(me.calls, 2, reason: '하트가 들어왔으니 GET /me/profile 을 한 번 더 부른다');
    });

    test('하트를 안 받은 투표(오늘 이미 받음 · 주 한도)는 다시 읽지 않는다', () async {
      repository
        ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
        ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: false));
      final container = await startWithProfile();

      await viewModel(container).vote('p1', PollChoice.a);
      await container.read(myProfileProvider.future);

      expect(me.calls, 1);
    });
  });

  test('이미 다른 기기에서 투표했으면 실패 알림을 주고 그 글만 다시 읽어 결과로 바꾼다', () async {
    repository
      ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
      ..voteResult = const FailureResult(ServerRejectedFailure('이미 투표했어요'))
      ..item = Success(itemFixture(myChoice: PollChoice.a));
    final container = await start();

    final notice = await viewModel(container).vote('p1', PollChoice.b);

    expect(notice?.failure, isA<ServerRejectedFailure>().having((f) => f.serverMessage, 'serverMessage', '이미 투표했어요'));
    expect(repository.fetchedItemIds, ['p1']);
    expect(container.read(communityFeedViewModelProvider).items.single.poll!.myChoice, PollChoice.a);
  });

  test('글이 사라졌으면(서버가 없다고 답함) 목록에서 뺀다', () async {
    repository
      ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
      ..voteResult = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'))
      ..item = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'));
    final container = await start();

    await viewModel(container).vote('p1', PollChoice.a);

    expect(container.read(communityFeedViewModelProvider).items, isEmpty);
  });

  test('연결 실패로는 글을 빼지 않는다', () async {
    repository
      ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
      ..voteResult = const FailureResult(NetworkFailure())
      ..item = const FailureResult(NetworkFailure());
    final container = await start();

    await viewModel(container).vote('p1', PollChoice.a);

    expect(container.read(communityFeedViewModelProvider).items, hasLength(1));
  });

  test('투표가 끝나기 전에 다시 눌러도 요청은 한 번', () async {
    repository
      ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: false))
      ..holdVote = Completer<void>();
    final container = await start();

    final first = viewModel(container).vote('p1', PollChoice.a);
    await viewModel(container).vote('p1', PollChoice.b);
    repository.holdVote!.complete();
    await first;

    expect(repository.votes, hasLength(1));
  });

  group('탭(전체 · 인기 · 내 질문 · 내 투표) — 탭별로 쌓아 두지 않고 바꿀 때마다 새로 받는다', () {
    final all = itemFixture(id: 'all-1');
    final popular = itemFixture(id: 'popular-1');
    final mine = itemFixture(id: 'mine-1', isMine: true);

    List<CommunityFeedTab> requestedTabs() => [for (final request in repository.pageRequests) request.tab];
    List<String> shownIds(ProviderContainer c) => [for (final poll in c.read(communityFeedViewModelProvider).items) poll.id];

    setUp(() {
      repository
        ..page = Success(FeedPage(items: [all], hasMore: true))
        ..pageByTab[CommunityFeedTab.popular] = Success(FeedPage(items: [popular], hasMore: false))
        ..pageByTab[CommunityFeedTab.mine] = Success(FeedPage(items: [mine], hasMore: false));
    });

    test('처음은 전체 탭이다', () async {
      final container = await start();
      expect(container.read(communityFeedViewModelProvider).tab, CommunityFeedTab.all);
      expect(requestedTabs(), [CommunityFeedTab.all]);
    });

    test('탭을 바꾸면 그 탭 첫 쪽을 새로 받아 목록을 갈아 끼운다', () async {
      final container = await start();

      await viewModel(container).selectTab(CommunityFeedTab.popular);

      expect(repository.pageRequests.last, (tab: CommunityFeedTab.popular, before: null, beforeId: null));
      expect(container.read(communityFeedViewModelProvider).tab, CommunityFeedTab.popular);
      expect(shownIds(container), ['popular-1']);
      expect(container.read(communityFeedViewModelProvider).hasMore, isFalse);
    });

    test('받는 동안에는 불러오는 중이고, 앞 탭 목록을 보이지 않는다', () async {
      final container = await start();
      repository.holdPage = Completer<void>();

      final switching = viewModel(container).selectTab(CommunityFeedTab.mine);

      final state = container.read(communityFeedViewModelProvider);
      expect(state.tab, CommunityFeedTab.mine);
      expect(state.isLoading, isTrue);
      expect(state.items, isEmpty);
      repository.holdPage!.complete();
      await switching;
      expect(shownIds(container), ['mine-1']);
    });

    test('지금 탭을 다시 누르면 다시 받지 않는다', () async {
      final container = await start();
      await viewModel(container).selectTab(CommunityFeedTab.all);
      expect(requestedTabs(), [CommunityFeedTab.all]);
    });

    test('탭 첫 쪽이 실패하면 그 탭의 실패 문구만 둔다 — 앞 탭 글을 남기지 않는다', () async {
      repository.pageByTab[CommunityFeedTab.voted] = const FailureResult(NetworkFailure());
      final container = await start();

      await viewModel(container).selectTab(CommunityFeedTab.voted);

      final state = container.read(communityFeedViewModelProvider);
      expect(state.items, isEmpty);
      expect(state.error, isA<NetworkFailure>());
      await viewModel(container).selectTab(CommunityFeedTab.all);
      expect(container.read(communityFeedViewModelProvider).error, isNull);
    });

    test('늦게 도착한 앞 탭 응답은 버린다 — 지금 탭 목록에 섞이지 않는다', () async {
      final container = await start();
      final slowHold = repository.holdPage = Completer<void>();
      final slow = viewModel(container).selectTab(CommunityFeedTab.popular);
      repository.holdPage = null;

      await viewModel(container).selectTab(CommunityFeedTab.mine);
      slowHold.complete();
      await slow;

      expect(container.read(communityFeedViewModelProvider).tab, CommunityFeedTab.mine);
      expect(shownIds(container), ['mine-1']);
    });

    test('늦게 도착한 앞 탭의 다음 쪽도 지금 탭 목록에 붙이지 않는다', () async {
      repository.nextPage = Success(FeedPage(items: [itemFixture(id: 'all-2')], hasMore: false));
      final container = await start();
      final slowHold = repository.holdPage = Completer<void>();
      final more = viewModel(container).loadMore();
      repository.holdPage = null;

      await viewModel(container).selectTab(CommunityFeedTab.mine);
      slowHold.complete();
      await more;

      expect(shownIds(container), ['mine-1']);
      expect(container.read(communityFeedViewModelProvider).isLoadingMore, isFalse);
    });

    test('진행 중 요청 합치기는 같은 탭끼리만 — 다른 탭 요청을 돌려주지 않는다', () async {
      final container = await start();
      final allHold = repository.holdPage = Completer<void>();
      final first = viewModel(container).refresh();
      final second = viewModel(container).refresh();
      expect(requestedTabs(), [CommunityFeedTab.all, CommunityFeedTab.all], reason: '같은 탭은 한 번만 간다');

      final popularHold = repository.holdPage = Completer<void>();
      final switching = viewModel(container).selectTab(CommunityFeedTab.popular);
      expect(requestedTabs().last, CommunityFeedTab.popular, reason: '전체 요청이 진행 중이어도 인기는 따로 받는다');

      allHold.complete();
      await Future.wait([first, second]);
      // 앞 탭 요청이 끝나며 지금 탭의 진행 중 표시를 지우면 안 된다 — 지우면 같은 탭 요청이 겹쳐 간다.
      final again = viewModel(container).refresh();
      expect(requestedTabs().where((tab) => tab == CommunityFeedTab.popular), hasLength(1));

      popularHold.complete();
      await Future.wait([switching, again]);
      expect(shownIds(container), ['popular-1']);
    });

    test('인기 탭은 한 쪽뿐이라 끝까지 내려도 더 부르지 않는다', () async {
      repository.pageByTab[CommunityFeedTab.popular] = Success(FeedPage(items: [popular], hasMore: true));
      final container = await start();
      await viewModel(container).selectTab(CommunityFeedTab.popular);

      await viewModel(container).loadMore();

      expect(requestedTabs(), [CommunityFeedTab.all, CommunityFeedTab.popular]);
    });

    test('내 질문 · 내 투표 탭은 같은 커서로 다음 쪽을 부른다', () async {
      final last = itemFixture(id: 'mine-1', createdAt: DateTime(2026, 9, 27, 13), isMine: true);
      repository.pageByTab[CommunityFeedTab.mine] = Success(FeedPage(items: [last], hasMore: true));
      final container = await start();
      await viewModel(container).selectTab(CommunityFeedTab.mine);

      await viewModel(container).loadMore();

      expect(repository.pageRequests.last, (tab: CommunityFeedTab.mine, before: last.createdAt, beforeId: 'mine-1'));
    });

    test('글을 올린 뒤에는 전체 탭으로 옮겨 새로 받는다', () async {
      final container = await start();
      await viewModel(container).selectTab(CommunityFeedTab.mine);

      await viewModel(container).showAllAfterPosting();

      expect(container.read(communityFeedViewModelProvider).tab, CommunityFeedTab.all);
      expect(requestedTabs(), [CommunityFeedTab.all, CommunityFeedTab.mine, CommunityFeedTab.all]);
      expect(shownIds(container), ['all-1']);
    });

    test('전체 탭에서 올렸어도 전체를 다시 받는다 — 방금 올린 글이 맨 위에 오게', () async {
      final container = await start();
      await viewModel(container).showAllAfterPosting();
      expect(requestedTabs(), [CommunityFeedTab.all, CommunityFeedTab.all]);
    });
  });

  group('게시물 · 카테고리(할 일 19)', () {
    test('피드는 투표 · 게시물이 섞인 줄을 그대로 보인다', () async {
      repository.page = Success(FeedPage(items: [itemFixture(), postFixture()], hasMore: false));
      final container = await start();

      final items = container.read(communityFeedViewModelProvider).items;
      expect([for (final item in items) item.id], ['p1', 't1']);
      expect(items.last.poll, isNull);
    });

    test('맨 아래가 게시물이어도 그 글의 시각과 id 로 다음 쪽을 부른다', () async {
      final last = postFixture(id: 't9', createdAt: DateTime(2026, 11, 24, 9));
      repository
        ..page = Success(FeedPage(items: [itemFixture(), last], hasMore: true))
        ..nextPage = Success(FeedPage(items: [postFixture(id: 't10')], hasMore: false));
      final container = await start();

      await viewModel(container).loadMore();

      expect(repository.pageRequests.last, (tab: CommunityFeedTab.all, before: last.createdAt, beforeId: 't9'));
      expect([for (final item in container.read(communityFeedViewModelProvider).items) item.id], ['p1', 't9', 't10']);
    });

    test('카테고리 탭은 그 탭 값으로 받고, 같은 커서로 다음 쪽을 부른다', () async {
      final love = postFixture(id: 'love-1', category: CommunityCategory.love);
      repository
        ..pageByTab[CommunityFeedTab.love] = Success(FeedPage(items: [love], hasMore: true))
        ..nextPage = const Success(FeedPage(items: [], hasMore: false));
      final container = await start();

      await viewModel(container).selectTab(CommunityFeedTab.of(CommunityCategory.love));
      await viewModel(container).loadMore();

      expect(repository.pageRequests.map((request) => request.tab),
          [CommunityFeedTab.all, CommunityFeedTab.love, CommunityFeedTab.love]);
      expect(repository.pageRequests.last.beforeId, 'love-1');
      expect(container.read(communityFeedViewModelProvider).tab, CommunityFeedTab.love);
    });

    test('투표 응답(옛 카드 모양, 카테고리 없음)을 얹어도 그 줄의 카테고리는 그대로다', () async {
      repository
        ..page = Success(FeedPage(items: [itemFixture(category: CommunityCategory.career)], hasMore: false))
        ..voteResult = Success(VoteOutcome(poll: pollFixture(aCount: 6, myChoice: PollChoice.a), rewarded: false));
      final container = await start();

      await viewModel(container).vote('p1', PollChoice.a);

      final item = container.read(communityFeedViewModelProvider).items.single;
      expect(item.category, CommunityCategory.career);
      expect(item.poll!.myChoice, PollChoice.a);
      expect(item.poll!.aCount, 6);
    });

    test('게시물 댓글 수도 상세에서 맞춘 숫자로 바뀐다', () async {
      repository.page = Success(FeedPage(items: [postFixture(commentCount: 1)], hasMore: false));
      final container = await start();

      viewModel(container).updateCommentCount('t1', 4);

      expect(container.read(communityFeedViewModelProvider).items.single.commentCount, 4);
    });

    test('내 게시물도 같은 길로 지운다', () async {
      repository.page = Success(FeedPage(items: [postFixture(isMine: true)], hasMore: false));
      final container = await start();

      expect(await viewModel(container).delete('t1'), isNull);

      expect(repository.deleted, ['t1']);
      expect(container.read(communityFeedViewModelProvider).items, isEmpty);
    });
  });

  test('내 글을 지우면 목록에서 빠지고, 실패하면 실패 종류를 주고 남긴다', () async {
    repository.page = Success(FeedPage(items: [itemFixture(isMine: true), itemFixture(id: 'p2', isMine: true)], hasMore: false));
    final container = await start();

    expect(await viewModel(container).delete('p1'), isNull);
    repository.deleteResult = const FailureResult(NetworkFailure());
    expect(await viewModel(container).delete('p2'), isA<NetworkFailure>());

    expect(container.read(communityFeedViewModelProvider).items.map((p) => p.id), ['p2']);
  });

  // 사용 통계 poll_vote — 서버가 투표를 받아 준 뒤에만, 이름만 남긴다(질문 id · 고른 보기 · 보상은 싣지 않는다).
  group('투표 분석(poll_vote)', () {
    test('투표가 받아들여지면 남긴다 — 보상이 없어도', () async {
      repository
        ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
        ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.b), rewarded: false));
      final container = await start();

      await viewModel(container).vote('p1', PollChoice.b);

      expect(analytics.calls, ['poll_vote']);
    });

    test('서버가 막으면(이미 투표 · 글 없음 · 연결 실패) 남기지 않는다', () async {
      repository
        ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
        ..voteResult = const FailureResult(ServerRejectedFailure('이미 투표했어요'))
        ..item = Success(itemFixture(myChoice: PollChoice.a));
      final container = await start();

      await viewModel(container).vote('p1', PollChoice.b);

      expect(analytics.calls, isEmpty);
    });

    test('이미 보내는 중인 투표를 또 눌러도 한 번만 남긴다', () async {
      repository
        ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
        ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: false));
      final container = await start();

      final first = viewModel(container).vote('p1', PollChoice.a);
      await viewModel(container).vote('p1', PollChoice.b);
      await first;

      expect(analytics.calls, ['poll_vote']);
    });
  });

  // 11-17: 알림 설정(#765)과 같은 FATAL — 받는 사이 로그아웃으로 버려진 뒤 늦게 온 답이 state · ref 를 쓰면 던진다.
  group('받는 도중 provider 가 버려지면 늦은 응답은 버린다', () {
    test('만들자마자 버려지면 첫 쪽을 읽지 않는다', () async {
      final local = ProviderContainer(overrides: [communityRepositoryProvider.overrideWithValue(repository)]);
      local.read(communityFeedViewModelProvider);

      local.dispose();

      await pumpEventQueue();
      expect(repository.pageRequests, isEmpty);
    });

    test('첫 쪽을 받는 도중', () async {
      final local = ProviderContainer(overrides: [communityRepositoryProvider.overrideWithValue(repository)]);
      final hold = repository.holdPage = Completer<void>();
      local.read(communityFeedViewModelProvider);
      final reading = local.read(communityFeedViewModelProvider.notifier).refresh();

      local.dispose();
      hold.complete();

      await expectLater(reading, completes);
    });

    test('다음 쪽을 받는 도중', () async {
      repository.page = Success(FeedPage(items: [itemFixture()], hasMore: true));
      final container = await start();
      final hold = repository.holdPage = Completer<void>();
      final loading = viewModel(container).loadMore();

      container.dispose();
      hold.complete();

      await expectLater(loading, completes);
    });

    test('투표 응답을 기다리는 도중', () async {
      repository
        ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
        ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: true));
      final container = await start();
      final hold = repository.holdVote = Completer<void>();
      final voting = viewModel(container).vote('p1', PollChoice.a);

      container.dispose();
      hold.complete();

      await expectLater(voting, completes);
    });

    test('투표가 막혀 그 글을 다시 읽는 도중', () async {
      repository
        ..page = Success(FeedPage(items: [itemFixture()], hasMore: false))
        ..voteResult = const FailureResult(ServerRejectedFailure('이미 투표했어요'))
        ..item = Success(itemFixture(myChoice: PollChoice.a));
      final container = await start();
      final hold = repository.holdItem = Completer<void>();
      final voting = viewModel(container).vote('p1', PollChoice.b);
      await pumpEventQueue();

      container.dispose();
      hold.complete();

      await expectLater(voting, completes);
    });

    test('지우기 응답을 기다리는 도중 — 지워졌으면 그대로 성공(null)을 준다', () async {
      repository.page = Success(FeedPage(items: [itemFixture(isMine: true)], hasMore: false));
      final container = await start();
      final hold = repository.holdDelete = Completer<void>();
      final deleting = viewModel(container).delete('p1');

      container.dispose();
      hold.complete();

      await expectLater(deleting, completion(isNull));
    });
  });
}
