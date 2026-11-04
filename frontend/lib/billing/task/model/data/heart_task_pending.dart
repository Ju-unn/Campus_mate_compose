/// 18a 검수 대기 목록의 한 줄 — `GET /heart-tasks` 의 `pending[]`. 같은 항목에서 아직 검수 중인 제출 하나다.
class HeartTaskPending {
  const HeartTaskPending({required this.id, required this.createdAt, required this.photoUrls});

  final String id;
  final DateTime createdAt;

  /// 사진 순서대로 서명 주소(10분). 서버가 서명에 실패한 장은 null — 장수는 그대로라 "사진 n장" 은 맞다.
  final List<String?> photoUrls;

  /// 모양이 다르면 던진다 — `ApiClient.send` 가 받아서 알 수 없는 오류로 바꾼다.
  factory HeartTaskPending.fromJson(Map<String, dynamic> json) {
    return HeartTaskPending(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      photoUrls: [for (final url in json['photo_urls'] as List<dynamic>) url as String?],
    );
  }
}
