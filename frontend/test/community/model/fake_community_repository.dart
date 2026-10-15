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

  /// 탭별 첫 쪽. 없는 탭은 [page] 를 돌려준다.
  final Map<PollFeedTab, Result<PollPage>> pageByTab = {};

  /// 채워 두면 목록 응답(첫 쪽 · 다음 쪽)이 이것이 끝날 때까지 멈춘다 — 늦게 도착한 응답 상황용.
  /// 부른 순간의 값을 잡으니, 요청 하나를 붙잡아 두고 비운 뒤 다음 요청은 바로 돌려줄 수 있다.
  Completer<void>? holdPage;
  Result<Poll>? poll;
  Result<void> createResult = const Success(null);
  Result<VoteOutcome>? voteResult;
  Result<void> deleteResult = const Success(null);

  /// 채워 두면 투표 응답이 이것이 끝날 때까지 멈춘다 — 누르는 도중 한 번 더 누르는 상황용.
  Completer<void>? holdVote;

  /// 채워 두면 지우기 응답이 이것이 끝날 때까지 멈춘다 — 삭제 중(15d-2 `EIEFb`) 상태용.
  Completer<void>? holdDelete;

  /// 채워 두면 올리기 응답이 이것이 끝날 때까지 멈춘다 — 올리는 중(17b `UqasS`) 상태용.
  Completer<void>? holdCreate;

  final List<({PollFeedTab tab, DateTime? before, String? beforeId})> pageRequests = [];
  final List<({String question, String optionA, String optionB})> created = [];
  final List<({String pollId, PollChoice choice})> votes = [];
  final List<String> fetchedPollIds = [];
  final List<String> deleted = [];

  @override
  Future<Result<PollPage>> fetchPolls({PollFeedTab tab = PollFeedTab.all, DateTime? before, String? beforeId}) async {
    pageRequests.add((tab: tab, before: before, beforeId: beforeId));
    if (holdPage case final hold?) await hold.future;
    return before == null ? (pageByTab[tab] ?? page) : (nextPage ?? page);
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
    await holdCreate?.future;
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
    await holdDelete?.future;
    return deleteResult;
  }
}
