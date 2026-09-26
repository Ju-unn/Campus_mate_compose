/// 09b 메인(pen `bpA8x`)이 그리는 값 한 벌. hero-today 문구는 고정이라 여기에 없다.
class HomeSummary {
  const HomeSummary({
    required this.unreadNotifications,
    required this.presentPeopleImages,
    required this.deliveredCards,
    required this.signups,
    required this.conversationsStarted,
    required this.reviewRating,
    required this.reviewCount,
    required this.campuses,
    required this.profileCompletionPercent,
  });

  /// 앱바 알림 종 배지
  final int unreadNotifications;

  /// mosaic-rail 사람 칸 그림.
  /// ponytail: 지금은 에셋 경로다 — 실제 API 가 URL 을 주면 칸 위젯을 네트워크 이미지로 바꾼다.
  final List<String> presentPeopleImages;

  /// stat-panel 세 칸
  final int deliveredCards;
  final int signups;
  final int conversationsStarted;

  /// review-strip
  final double reviewRating;
  final int reviewCount;

  /// campus-strip
  final List<String> campuses;

  /// 사진 더 올리기 카드의 완성도(0~100)
  final int profileCompletionPercent;
}
