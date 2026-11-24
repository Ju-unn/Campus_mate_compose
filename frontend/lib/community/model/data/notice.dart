/// 커뮤니티 공지 한 줄(할 일 21 · `GET /community/notices` 의 item, 상세 `/community/items/{id}` 의 kind "notice").
/// 작성자 칸은 없다 — 화면이 늘 "CampusMate 운영자" 로 그린다. 제목 · 본문은 서버 글자 그대로 보인다(HTML 해석 · 링크 자동 열기 없음).
/// [imageUrl] 은 **서버가 만든 주소만** 쓴다 — 앱이 주소를 조립하지 않는다(보안 기준 21-4).
class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.text,
    required this.createdAt,
    this.imageUrl,
    this.isNew = false,
    this.commentCount = 0,
  });

  final String id;
  final String title;
  final String text;
  final DateTime createdAt;
  final String? imageUrl;

  /// 서버 시계로 7일 안(NEW 배지). 상세 응답에는 이 칸이 없어 false 로 읽는다 — 상세는 배지를 그리지 않는다.
  final bool isNew;
  final int commentCount;

  /// 댓글을 쓰거나 지운 뒤 숫자만 맞춘 사본.
  Notice withCommentCount(int count) => Notice(
      id: id, title: title, text: text, createdAt: createdAt, imageUrl: imageUrl, isNew: isNew, commentCount: count);

  factory Notice.fromJson(Map<String, dynamic> json) {
    return Notice(
      id: json['id'] as String,
      title: json['title'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      imageUrl: json['image_url'] as String?,
      isNew: json['is_new'] as bool? ?? false,
      commentCount: json['comment_count'] as int? ?? 0,
    );
  }
}
