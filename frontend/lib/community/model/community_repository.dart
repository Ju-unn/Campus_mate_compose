import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/poll.dart';

/// 한 번에 받아 오는 질문 수. 서버 `POLL_PAGE_SIZE` 와 같은 값이다.
const int pollPageSize = 20;

class PollPage {
  const PollPage({required this.polls, required this.hasMore});

  final List<Poll> polls;
  final bool hasMore;

  factory PollPage.fromJson(Map<String, dynamic> json) {
    return PollPage(
      polls: (json['polls'] as List<dynamic>)
          .map((item) => Poll.fromJson(item as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool,
    );
  }
}

/// 투표 결과. [rewarded] 면 하루 첫 투표 하트 10개가 들어갔다.
class VoteOutcome {
  const VoteOutcome({required this.poll, required this.rewarded});

  final Poll poll;
  final bool rewarded;

  factory VoteOutcome.fromJson(Map<String, dynamic> json) {
    return VoteOutcome(
      poll: Poll.fromJson(json['poll'] as Map<String, dynamic>),
      rewarded: json['rewarded'] as bool,
    );
  }
}

/// 커뮤니티 탭이 쓰는 서버 호출 전부. 화면은 이 인터페이스만 보고 `Http…` 구현을 모른다.
abstract interface class CommunityRepository {
  /// [before] · [beforeId] 는 화면 맨 아래 글의 값을 그대로 보낸다 —
  /// 시각만 보내면 같은 시각에 올라간 두 글이 쪽 경계에서 하나 빠진다.
  Future<Result<PollPage>> fetchPolls({DateTime? before, String? beforeId});
  Future<Result<Poll>> fetchPoll(String pollId);
  Future<Result<void>> createPoll({required String question, required String optionA, required String optionB});

  /// 되돌릴 수 없다(DESIGN §8.11).
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice);

  /// 내 글만 지워진다. 남의 글 id 면 서버가 "없음" 으로 답한다.
  Future<Result<void>> deletePoll(String pollId);
}
