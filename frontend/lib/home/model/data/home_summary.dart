import 'package:campus_mate/home/model/data/cohort_wait.dart';

/// 09b 메인(pen `k13Z5C`)이 그리는 값 한 벌. hero-today 문구는 고정이라 여기에 없다. 레일 사람 칸은 따로 받는다(`HomePeople`).
class HomeSummary {
  const HomeSummary({
    required this.deliveredCards,
    required this.signups,
    required this.conversationsStarted,
    required this.reviewRating,
    required this.reviewCount,
    required this.campuses,
    required this.profileCompletionPercent,
    this.cohort,
    this.banners = const [],
  });

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

  /// 우리 학교가 아직 안 열렸으면 19 대기 화면 값, 열렸으면 null
  final CohortWait? cohort;

  /// 홈 배너 슬라이드(홈 v3, 서버가 기간 · 순서를 골라 준다). 옛 서버 · 배너 없음이면 빈 목록이고 화면이 칸째 숨긴다.
  final List<HomeBanner> banners;
}

/// 홈 배너 한 장 — 서버 공개 그림 주소와 그림 속 문구(화면 읽기용, 그림에 이미 글자가 들어 있다).
class HomeBanner {
  const HomeBanner({required this.imageUrl, required this.altText});

  factory HomeBanner.fromJson(Map<String, dynamic> json) =>
      HomeBanner(imageUrl: json['image_url'] as String, altText: json['alt_text'] as String);

  final String imageUrl;
  final String altText;

  @override
  bool operator ==(Object other) => other is HomeBanner && other.imageUrl == imageUrl && other.altText == altText;

  @override
  int get hashCode => Object.hash(imageUrl, altText);
}
