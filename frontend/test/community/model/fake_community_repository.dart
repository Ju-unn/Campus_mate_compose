import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/poll.dart';

Poll pollFixture({
  String id = 'p1',
  String question = '첫 데이트 더치페이',
  String optionA = defaultOptionA,
  String optionB = defaultOptionB,
  DateTime? createdAt,
  int aCount = 5,
  int bCount = 3,
  PollChoice? myChoice,
  bool isMine = false,
}) =>
    Poll(
      id: id,
      question: question,
      optionA: optionA,
      optionB: optionB,
      createdAt: createdAt ?? DateTime(2026, 9, 27, 14),
      aCount: aCount,
      bCount: bCount,
      myChoice: myChoice,
      isMine: isMine,
    );

/// 화면 · ViewModel 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeCommunityRepository implements CommunityRepository {
  Result<PollPage> page = const Success(PollPage(polls: [], hasMore: false));

  /// 채워 두면 커서가 있는 요청(다음 쪽)에 이것을 돌려준다.
  Result<PollPage>? nextPage;
  Result<Poll>? poll;
  Result<void> createResult = const Success(null);
  Result<VoteOutcome>? voteResult;
  Result<void> deleteResult = const Success(null);

  /// 채워 두면 투표 응답이 이것이 끝날 때까지 멈춘다 — 누르는 도중 한 번 더 누르는 상황용.
  Completer<void>? holdVote;

  final List<({DateTime? before, String? beforeId})> pageRequests = [];
  final List<({String question, String optionA, String optionB})> created = [];
  final List<({String pollId, PollChoice choice})> votes = [];
  final List<String> fetchedPollIds = [];
  final List<String> deleted = [];

  @override
  Future<Result<PollPage>> fetchPolls({DateTime? before, String? beforeId}) async {
    pageRequests.add((before: before, beforeId: beforeId));
    return before == null ? page : (nextPage ?? page);
  }

  @override
  Future<Result<Poll>> fetchPoll(String pollId) async {
    fetchedPollIds.add(pollId);
    return poll!;
  }

  @override
  Future<Result<void>> createPoll({
    required String question,
    required String optionA,
    required String optionB,
  }) async {
    created.add((question: question, optionA: optionA, optionB: optionB));
    return createResult;
  }

  @override
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice) async {
    votes.add((pollId: pollId, choice: choice));
    await holdVote?.future;
    return voteResult!;
  }

  @override
  Future<Result<void>> deletePoll(String pollId) async {
    deleted.add(pollId);
    return deleteResult;
  }
}
