/// 무엇을 신고하는가 — 프로필 · 메시지 · 지인 리뷰(20c, 차단 안 함 — 서버 B3) · 투표 글(차단 안 함 — 서버 #191).
class ReportTarget {
  /// 채팅방 앱바 메뉴 · 14c 하단 액션 행에서 온 신고.
  const ReportTarget.profile(String profileId) : _type = 'profile', _id = profileId;

  /// 말풍선 롱프레스에서 온 신고. 서버가 이 id 로 본문 · 보낸 시각을 스냅샷에 담는다(B1 ③).
  const ReportTarget.message(String messageId) : _type = 'message', _id = messageId;

  const ReportTarget.friendReview(String reviewId) : _type = 'friend_review', _id = reviewId;

  /// 15d 목록 · 17c 상세의 투표 카드 머리줄에서 온 신고 — 남의 글만(내 글은 서버도 404).
  const ReportTarget.poll(String pollId) : _type = 'poll', _id = pollId;

  final String _type;
  final String _id;

  Map<String, String> toJson() => {'target_type': _type, 'target_id': _id};
}
