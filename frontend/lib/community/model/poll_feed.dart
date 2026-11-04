import 'package:campus_mate/community/model/poll.dart';

/// 한 번에 받아 오는 질문 수. 서버 `POLL_PAGE_SIZE` 와 같은 값이다.
const int pollPageSize = 20;

/// 15d 탭 줄(pen `XfcKQ`). 이름이 서버 `tab` 쿼리 값(`PollTab`)과 같다.
/// 인기는 최근 7일 참여 수 순 상위 20개 한 쪽뿐이라 서버가 늘 "더 없음" 으로 답한다. 나머지는 올린 시각 순 · 같은 커서.
enum PollFeedTab { all, popular, mine, voted }

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

/// 투표 결과. [rewarded] 면 하루 첫 투표 하트 5개가 들어갔다(2026-10-16 개정, 종전 10).
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
