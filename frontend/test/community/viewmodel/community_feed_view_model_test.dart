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

    expect(repository.pageRequests.last, (before: last.createdAt, beforeId: 'p2'));
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

    expect(message, pollRewardMessage);
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

  test('내 글을 지우면 목록에서 빠지고, 실패하면 문구를 주고 남긴다', () async {
    repository.page = Success(PollPage(polls: [pollFixture(isMine: true), pollFixture(id: 'p2', isMine: true)], hasMore: false));
    final container = await start();

    expect(await viewModel(container).delete('p1'), isNull);
    repository.deleteResult = const FailureResult(NetworkFailure());
    expect(await viewModel(container).delete('p2'), '네트워크 연결을 확인해 주세요');

    expect(container.read(communityFeedViewModelProvider).polls.map((p) => p.id), ['p2']);
  });
}
