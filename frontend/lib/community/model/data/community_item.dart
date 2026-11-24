import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/server_text.dart';

/// 서버 `POST_MAX_LENGTH` · DB `polls_question_length`(게시물 1~500)와 같은 값이다(코드 포인트로 센다).
const int postBodyMaxLength = 500;

/// 커뮤니티 글의 종류. 글쓰기에서 고르고, 종류마다 본문(투표는 질문) 글자 상한이 다르다.
enum CommunityKind {
  poll(pollQuestionMaxLength),
  post(postBodyMaxLength);

  const CommunityKind(this.maxLength);

  final int maxLength;

  /// 서버가 받을 모양인지 **미리** 본다 — 기준은 서버다(보안 기준 2·3·9 의 1).
  /// 서버와 같게 앞뒤 공백을 깎은 뒤 코드 포인트로 재고, 0폭 문자 · 공백만이면 빈 글이다.
  bool accepts(String text) => fitsServerText(text, maxLength);
}

/// 피드 한 줄 — 투표 또는 게시물(`GET /community/feed` · `/community/items/{id}` 의 item).
/// **작성자가 누구인지는 모른다** — 서버가 [isMine] 만 준다. 투표면 [poll] 에 기존 [Poll] 을 그대로 담아
/// 투표 카드 · 투표 상세가 지금 모양 그대로 쓴다. 게시물이면 [poll] 이 null 이다.
class CommunityItem {
  /// 투표 줄. 공통 칸은 [poll] 에서 읽는다 — 두 곳에 따로 들고 있다 어긋나지 않게.
  CommunityItem.ofPoll(Poll this.poll, {required this.category})
      : id = poll.id,
        text = poll.question,
        createdAt = poll.createdAt,
        isMine = poll.isMine,
        commentCount = poll.commentCount;

  const CommunityItem.post({
    required this.id,
    required this.category,
    required this.text,
    required this.createdAt,
    this.isMine = false,
    this.commentCount = 0,
  }) : poll = null;

  final String id;
  final CommunityCategory category;

  /// 게시물 본문, 투표면 질문.
  final String text;
  final DateTime createdAt;
  final bool isMine;
  final int commentCount;
  final Poll? poll;

  CommunityKind get kind => poll == null ? CommunityKind.post : CommunityKind.poll;

  /// 댓글을 쓰거나 지운 뒤 숫자만 맞춘 사본.
  CommunityItem withCommentCount(int count) {
    final poll = this.poll;
    if (poll != null) return CommunityItem.ofPoll(poll.withCommentCount(count), category: category);
    return CommunityItem.post(
        id: id, category: category, text: text, createdAt: createdAt, isMine: isMine, commentCount: count);
  }

  /// 투표 응답 `POST /community/polls/{id}/votes` 는 옛 카드 모양(`{poll, rewarded}`, 카테고리 없음)이다 —
  /// **옛 카드 → 피드 한 줄 변환은 여기 한 곳**. 카테고리는 이 줄 값을 지킨다.
  CommunityItem withVote(Poll voted) => CommunityItem.ofPoll(voted, category: category);

  factory CommunityItem.fromJson(Map<String, dynamic> json) {
    final category = CommunityCategory.fromWire(json['category']);
    if (json['poll'] case final Map<String, dynamic> poll) {
      // 기존 Poll.fromJson 이 읽는 옛 카드 모양으로 펼친다 — 질문은 text 칸이다.
      return CommunityItem.ofPoll(Poll.fromJson({...json, ...poll, 'question': json['text']}), category: category);
    }
    return CommunityItem.post(
      id: json['id'] as String,
      category: category,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      isMine: json['is_mine'] as bool,
      commentCount: json['comment_count'] as int? ?? 0,
    );
  }
}
