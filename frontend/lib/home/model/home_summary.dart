import 'package:campus_mate/home/model/cohort_wait.dart';

/// 09b 메인(pen `bpA8x`)이 그리는 값 한 벌. hero-today 문구는 고정이라 여기에 없다. 레일 사람 칸은 따로 받는다(`HomePeople`).
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
}
