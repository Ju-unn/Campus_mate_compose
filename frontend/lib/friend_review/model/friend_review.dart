/// 20b/20c 목록 한 줄. 서버 `ReviewItem`(API 계약)을 그대로 옮긴다.
class FriendReview {
  const FriendReview({
    required this.id,
    required this.nickname,
    required this.tags,
    required this.createdAt,
    this.avatarUrl,
    this.university,
    this.comment,
  });

  final String id;

  /// 카드 머리의 사람. 서버 응답은 `reviewer`(20c · 14c · 14d — 쓴 사람) 또는 `reviewee`(20e — 받은 사람)로
  /// 묶여 오지만 화면은 한 줄만 쓰므로 여기서 펼쳐 둔다.
  final String nickname;
  final String? avatarUrl;
  final String? university;
  final List<String> tags;

  /// 다듬어 비었으면 서버가 이미 null 로 보낸다(HttpFriendReviewRepository.create 쪽 참고).
  final String? comment;

  /// 서버는 UTC(+00:00) 로 준다. 화면에서 보여줄 때 로컬로 바꾼다.
  final DateTime createdAt;

  factory FriendReview.fromJson(Map<String, dynamic> json) {
    final person = (json['reviewer'] ?? json['reviewee']) as Map<String, dynamic>;
    return FriendReview(
      id: json['id'] as String,
      nickname: person['nickname'] as String,
      avatarUrl: person['avatar_url'] as String?,
      university: person['university'] as String?,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// 리뷰를 쓸 상대. 20b 머리(`GET /friend-reviews/targets/{id}`)와 20e 위 "리뷰를 기다리는 친구"
/// 한 줄(`GET /friend-reviews/writable`)이 같이 쓴다.
class ReviewTarget {
  const ReviewTarget({required this.profileId, required this.nickname, this.avatarUrl, this.university});

  final String profileId;
  final String nickname;
  final String? avatarUrl;

  /// "리뷰를 기다리는 친구" 줄만 싣는다 — 20b 머리 응답에는 없다.
  final String? university;

  factory ReviewTarget.fromJson(Map<String, dynamic> json) {
    return ReviewTarget(
      profileId: json['profile_id'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatar_url'] as String?,
      university: json['university'] as String?,
    );
  }
}
