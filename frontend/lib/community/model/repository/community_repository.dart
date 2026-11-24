import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/data/feed_page.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';

/// 커뮤니티 탭이 쓰는 서버 호출 전부. 화면은 이 인터페이스만 보고 `Http…` 구현을 모른다.
/// 글(투표 · 게시물)은 새 길 `/community/feed` · `/community/items` 를 쓴다(할 일 19). 옛 길 `/community/polls` 는 1.0.6 몫이다.
abstract interface class CommunityRepository {
  /// 투표 · 게시물이 섞인 피드. [before] 는 화면 맨 아래 글의 값을 그대로 보낸다.
  Future<Result<FeedPage<CommunityItem>>> fetchFeed({CommunityFeedTab tab = CommunityFeedTab.all, PageCursor? before});
  Future<Result<CommunityItem>> fetchItem(String itemId);

  /// 투표 올리기. 하루 10개(게시물과 합산)를 넘으면 429.
  Future<Result<void>> createPoll({
    required CommunityCategory category,
    required String question,
    required String optionA,
    required String optionB,
  });

  /// 게시물 올리기(글만 · 익명 · 500자). 하루 10개(투표와 합산)를 넘으면 429.
  Future<Result<void>> createPost({required CommunityCategory category, required String body});

  /// 되돌릴 수 없다(DESIGN §8.11). 응답은 옛 카드 모양이라 [CommunityItem.withVote] 로 피드 줄에 얹는다.
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice);

  /// 내 글만 지워진다. 남의 글 id 면 서버가 "없음" 으로 답한다.
  Future<Result<void>> deleteItem(String itemId);

  /// 오래된 순 10개. [after] 는 **서버에서 받은** 마지막 댓글의 값을 그대로 보낸다. 투표 · 게시물 댓글이 같은 길이다.
  Future<Result<FeedPage<PollComment>>> fetchComments(String itemId, {PageCursor? after});

  /// 1~200자. 앞뒤 공백은 서버도 깎지만 앱이 먼저 정리해 보낸다. 하루 50개를 넘으면 429.
  Future<Result<PollComment>> addComment(String itemId, String body);

  /// 내 댓글이나 내 글에 달린 댓글. 남의 것 · 없는 것은 서버가 똑같이 404 로 답한다.
  Future<Result<void>> deleteComment(String commentId);
}
