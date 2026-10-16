import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../me/model/fake_me_repository.dart';
import '../model/fake_community_repository.dart';

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

  Future<ProviderContainer> start() async {
    final container = ProviderContainer(overrides: [communityRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    container.read(communityFeedViewModelProvider);
    await container.read(communityFeedViewModelProvider.notifier).refresh();
    return container;
  }

  CommunityFeedViewModel viewModel(ProviderContainer c) => c.read(communityFeedViewModelProvider.notifier);

  setUp(() => repository = FakeCommunityRepository());

  test('열면 첫 쪽을 읽는다', () async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: true));
    final container = await start();
    final state = container.read(communityFeedViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.polls.single.id, 'p1');
    expect(state.hasMore, isTrue);
  });

  test('첫 쪽이 실패하면 문구를 둔다', () async {
    repository.page = const FailureResult(NetworkFailure());
    final container = await start();
    expect(container.read(communityFeedViewModelProvider).errorMessage, '네트워크 연결을 확인해 주세요');
  });

  test('더 내리면 맨 아래 글의 시각과 id 를 커서로 보내고 뒤에 붙인다(겹친 글은 거른다)', () async {
    final last = pollFixture(id: 'p2', createdAt: DateTime(2026, 9, 27, 13));
    repository
      ..page = Success(PollPage(polls: [pollFixture(), last], hasMore: true))
      ..nextPage = Success(PollPage(polls: [last, pollFixture(id: 'p3')], hasMore: false));
    final container = await start();

    await viewModel(container).loadMore();

    expect(repository.pageRequests.last, (tab: PollFeedTab.all, before: last.createdAt, beforeId: 'p2'));
    expect(container.read(communityFeedViewModelProvider).polls.map((p) => p.id), ['p1', 'p2', 'p3']);
    expect(container.read(communityFeedViewModelProvider).hasMore, isFalse);
  });

  test('더 없으면 요청하지 않는다', () async {
    repository.page = Success(PollPage(polls: [pollFixture()], hasMore: false));
    final container = await start();
    await viewModel(container).loadMore();
    expect(repository.pageRequests, hasLength(1));
  });

  test('투표하면 그 글을 서버 값으로 바꾸고, 보상이면 토스트 문구를 준다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(aCount: 6, myChoice: PollChoice.a), rewarded: true));
    final container = await start();

    final message = await viewModel(container).vote('p1', PollChoice.a);

    expect(message, '하트 5개를 받았어요'); // 하루 첫 투표 5하트(2026-10-16 사용자 확정, 종전 10)
    expect(container.read(communityFeedViewModelProvider).polls.single.myChoice, PollChoice.a);
  });

  test('보상이 없으면 토스트도 없다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
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
        ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
        ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: true));
      final container = await startWithProfile();

      await viewModel(container).vote('p1', PollChoice.a);
      await container.read(myProfileProvider.future);

      expect(me.calls, 2, reason: '하트가 들어왔으니 GET /me/profile 을 한 번 더 부른다');
    });

    test('하트를 안 받은 투표(오늘 이미 받음 · 주 한도)는 다시 읽지 않는다', () async {
      repository
        ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
        ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.a), rewarded: false));
      final container = await startWithProfile();

      await viewModel(container).vote('p1', PollChoice.a);
      await container.read(myProfileProvider.future);

      expect(me.calls, 1);
    });
  });

  test('이미 다른 기기에서 투표했으면 문구를 주고 그 글만 다시 읽어 결과로 바꾼다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = const FailureResult(ServerRejectedFailure('이미 투표했어요'))
      ..poll = Success(pollFixture(myChoice: PollChoice.a));
    final container = await start();

    final message = await viewModel(container).vote('p1', PollChoice.b);

    expect(message, '이미 투표했어요');
    expect(repository.fetchedPollIds, ['p1']);
    expect(container.read(communityFeedViewModelProvider).polls.single.myChoice, PollChoice.a);
  });

  test('글이 사라졌으면(서버가 없다고 답함) 목록에서 뺀다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'))
      ..poll = const FailureResult(ServerRejectedFailure('질문을 찾을 수 없어요'));
    final container = await start();

    await viewModel(container).vote('p1', PollChoice.a);

    expect(container.read(communityFeedViewModelProvider).polls, isEmpty);
  });

  test('연결 실패로는 글을 빼지 않는다', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = const FailureResult(NetworkFailure())
      ..poll = const FailureResult(NetworkFailure());
    final container = await start();

    await viewModel(container).vote('p1', PollChoice.a);

    expect(container.read(communityFeedViewModelProvider).polls, hasLength(1));
  });

  test('투표가 끝나기 전에 다시 눌러도 요청은 한 번', () async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
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
    final all = pollFixture(id: 'all-1');
    final popular = pollFixture(id: 'popular-1');
    final mine = pollFixture(id: 'mine-1', isMine: true);

    List<PollFeedTab> requestedTabs() => [for (final request in repository.pageRequests) request.tab];
    List<String> shownIds(ProviderContainer c) => [for (final poll in c.read(communityFeedViewModelProvider).polls) poll.id];

    setUp(() {
      repository
        ..page = Success(PollPage(polls: [all], hasMore: true))
        ..pageByTab[PollFeedTab.popular] = Success(PollPage(polls: [popular], hasMore: false))
        ..pageByTab[PollFeedTab.mine] = Success(PollPage(polls: [mine], hasMore: false));
    });

    test('처음은 전체 탭이다', () async {
      final container = await start();
      expect(container.read(communityFeedViewModelProvider).tab, PollFeedTab.all);
      expect(requestedTabs(), [PollFeedTab.all]);
    });

    test('탭을 바꾸면 그 탭 첫 쪽을 새로 받아 목록을 갈아 끼운다', () async {
      final container = await start();

      await viewModel(container).selectTab(PollFeedTab.popular);

      expect(repository.pageRequests.last, (tab: PollFeedTab.popular, before: null, beforeId: null));
      expect(container.read(communityFeedViewModelProvider).tab, PollFeedTab.popular);
      expect(shownIds(container), ['popular-1']);
      expect(container.read(communityFeedViewModelProvider).hasMore, isFalse);
    });

    test('받는 동안에는 불러오는 중이고, 앞 탭 목록을 보이지 않는다', () async {
      final container = await start();
      repository.holdPage = Completer<void>();

      final switching = viewModel(container).selectTab(PollFeedTab.mine);

      final state = container.read(communityFeedViewModelProvider);
      expect(state.tab, PollFeedTab.mine);
      expect(state.isLoading, isTrue);
      expect(state.polls, isEmpty);
      repository.holdPage!.complete();
      await switching;
      expect(shownIds(container), ['mine-1']);
    });

    test('지금 탭을 다시 누르면 다시 받지 않는다', () async {
      final container = await start();
      await viewModel(container).selectTab(PollFeedTab.all);
      expect(requestedTabs(), [PollFeedTab.all]);
    });

    test('탭 첫 쪽이 실패하면 그 탭의 실패 문구만 둔다 — 앞 탭 글을 남기지 않는다', () async {
      repository.pageByTab[PollFeedTab.voted] = const FailureResult(NetworkFailure());
      final container = await start();

      await viewModel(container).selectTab(PollFeedTab.voted);

      final state = container.read(communityFeedViewModelProvider);
      expect(state.polls, isEmpty);
      expect(state.errorMessage, '네트워크 연결을 확인해 주세요');
      await viewModel(container).selectTab(PollFeedTab.all);
      expect(container.read(communityFeedViewModelProvider).errorMessage, isNull);
    });

    test('늦게 도착한 앞 탭 응답은 버린다 — 지금 탭 목록에 섞이지 않는다', () async {
      final container = await start();
      final slowHold = repository.holdPage = Completer<void>();
      final slow = viewModel(container).selectTab(PollFeedTab.popular);
      repository.holdPage = null;

      await viewModel(container).selectTab(PollFeedTab.mine);
      slowHold.complete();
      await slow;

      expect(container.read(communityFeedViewModelProvider).tab, PollFeedTab.mine);
      expect(shownIds(container), ['mine-1']);
    });

    test('늦게 도착한 앞 탭의 다음 쪽도 지금 탭 목록에 붙이지 않는다', () async {
      repository.nextPage = Success(PollPage(polls: [pollFixture(id: 'all-2')], hasMore: false));
      final container = await start();
      final slowHold = repository.holdPage = Completer<void>();
      final more = viewModel(container).loadMore();
      repository.holdPage = null;

      await viewModel(container).selectTab(PollFeedTab.mine);
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
      expect(requestedTabs(), [PollFeedTab.all, PollFeedTab.all], reason: '같은 탭은 한 번만 간다');

      final popularHold = repository.holdPage = Completer<void>();
      final switching = viewModel(container).selectTab(PollFeedTab.popular);
      expect(requestedTabs().last, PollFeedTab.popular, reason: '전체 요청이 진행 중이어도 인기는 따로 받는다');

      allHold.complete();
      await Future.wait([first, second]);
      // 앞 탭 요청이 끝나며 지금 탭의 진행 중 표시를 지우면 안 된다 — 지우면 같은 탭 요청이 겹쳐 간다.
      final again = viewModel(container).refresh();
      expect(requestedTabs().where((tab) => tab == PollFeedTab.popular), hasLength(1));

      popularHold.complete();
      await Future.wait([switching, again]);
      expect(shownIds(container), ['popular-1']);
    });

    test('인기 탭은 한 쪽뿐이라 끝까지 내려도 더 부르지 않는다', () async {
      repository.pageByTab[PollFeedTab.popular] = Success(PollPage(polls: [popular], hasMore: true));
      final container = await start();
      await viewModel(container).selectTab(PollFeedTab.popular);

      await viewModel(container).loadMore();

      expect(requestedTabs(), [PollFeedTab.all, PollFeedTab.popular]);
    });

    test('내 질문 · 내 투표 탭은 같은 커서로 다음 쪽을 부른다', () async {
      final last = pollFixture(id: 'mine-1', createdAt: DateTime(2026, 9, 27, 13), isMine: true);
      repository.pageByTab[PollFeedTab.mine] = Success(PollPage(polls: [last], hasMore: true));
      final container = await start();
      await viewModel(container).selectTab(PollFeedTab.mine);

      await viewModel(container).loadMore();

      expect(repository.pageRequests.last, (tab: PollFeedTab.mine, before: last.createdAt, beforeId: 'mine-1'));
    });

    test('글을 올린 뒤에는 전체 탭으로 옮겨 새로 받는다', () async {
      final container = await start();
      await viewModel(container).selectTab(PollFeedTab.mine);

      await viewModel(container).showAllAfterPosting();

      expect(container.read(communityFeedViewModelProvider).tab, PollFeedTab.all);
      expect(requestedTabs(), [PollFeedTab.all, PollFeedTab.mine, PollFeedTab.all]);
      expect(shownIds(container), ['all-1']);
    });

    test('전체 탭에서 올렸어도 전체를 다시 받는다 — 방금 올린 글이 맨 위에 오게', () async {
      final container = await start();
      await viewModel(container).showAllAfterPosting();
      expect(requestedTabs(), [PollFeedTab.all, PollFeedTab.all]);
    });
  });

  test('내 글을 지우면 목록에서 빠지고, 실패하면 문구를 주고 남긴다', () async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true), pollFixture(id: 'p2', isMine: true)], hasMore: false));
    final container = await start();

    expect(await viewModel(container).delete('p1'), isNull);
    repository.deleteResult = const FailureResult(NetworkFailure());
    expect(await viewModel(container).delete('p2'), '네트워크 연결을 확인해 주세요');

    expect(container.read(communityFeedViewModelProvider).polls.map((p) => p.id), ['p2']);
  });
}
