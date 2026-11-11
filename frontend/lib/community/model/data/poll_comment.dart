/// 댓글 글자 수 상한. 서버 `COMMENT_MAX_LENGTH` · DB `poll_comments_body_length` 와 같은 값이다(코드 포인트로 센다).
const int commentMaxLength = 200;

/// O/X 글의 댓글 한 줄. **작성자가 누구인지는 모른다** — 서버가 글 안의 익명 번호([aliasNo])와
/// 글쓴이 여부([isPostAuthor]) · 내 것인지([isMine]) · 지울 수 있는지([canDelete])만 준다.
class PollComment {
  const PollComment({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.aliasNo,
    required this.isPostAuthor,
    required this.isMine,
    required this.canDelete,
  });

  final String id;
  final String body;
  final DateTime createdAt;

  /// 글 안의 익명 번호("익명N"). **글쓴이 댓글은 번호가 없어 null** 이다(서버 `poll_comments_page`).
  final int? aliasNo;
  final bool isPostAuthor;
  final bool isMine;

  /// 내 댓글이거나 내 글에 달린 댓글이면 true. "…" 메뉴에 삭제를 넣을지를 정한다.
  final bool canDelete;

  factory PollComment.fromJson(Map<String, dynamic> json) {
    return PollComment(
      id: json['id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      aliasNo: json['alias_no'] as int?,
      isPostAuthor: json['is_post_author'] as bool,
      isMine: json['is_mine'] as bool,
      canDelete: json['can_delete'] as bool,
    );
  }
}

class PollCommentPage {
  const PollCommentPage({required this.comments, required this.hasMore});

  final List<PollComment> comments;
  final bool hasMore;

  factory PollCommentPage.fromJson(Map<String, dynamic> json) {
    return PollCommentPage(
      comments: (json['items'] as List<dynamic>)
          .map((item) => PollComment.fromJson(item as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool,
    );
  }
}
