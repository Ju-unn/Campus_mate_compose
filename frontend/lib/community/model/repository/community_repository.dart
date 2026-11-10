import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/model/data/poll_feed.dart';

/// 커뮤니티 탭이 쓰는 서버 호출 전부. 화면은 이 인터페이스만 보고 `Http…` 구현을 모른다.
abstract interface class CommunityRepository {
  /// [before] · [beforeId] 는 화면 맨 아래 글의 값을 그대로 보낸다 —
  /// 시각만 보내면 같은 시각에 올라간 두 글이 쪽 경계에서 하나 빠진다.
  Future<Result<PollPage>> fetchPolls({PollFeedTab tab = PollFeedTab.all, DateTime? before, String? beforeId});
  Future<Result<Poll>> fetchPoll(String pollId);
  Future<Result<void>> createPoll({required String question, required String optionA, required String optionB});

  /// 되돌릴 수 없다(DESIGN §8.11).
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice);

  /// 내 글만 지워진다. 남의 글 id 면 서버가 "없음" 으로 답한다.
  Future<Result<void>> deletePoll(String pollId);

  /// 오래된 순 10개. [after] · [afterId] 는 **서버에서 받은** 마지막 댓글의 값을 그대로 보낸다 —
  /// 하나만 보내면 서버가 422 로 막는다.
  Future<Result<PollCommentPage>> fetchComments(String pollId, {DateTime? after, String? afterId});

  /// 1~200자. 앞뒤 공백은 서버도 깎지만 앱이 먼저 정리해 보낸다. 하루 50개를 넘으면 429.
  Future<Result<PollComment>> addComment(String pollId, String body);

  /// 내 댓글이나 내 글에 달린 댓글. 남의 것 · 없는 것은 서버가 똑같이 404 로 답한다.
  Future<Result<void>> deleteComment(String commentId);
}
