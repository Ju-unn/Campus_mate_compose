/// 간격 토큰 (DESIGN.md §4.1). 기본 단위 4px. 위젯은 이 상수만 읽는다.
abstract final class AppSpacing {
  /// 아이콘과 라벨 사이, 칩 내부 세로
  static const double xxs = 4;

  /// 인접 요소 최소 간격, 터치 타깃 사이
  static const double xs = 8;

  /// 리스트 행 내부 세로 패딩
  static const double sm = 12;

  /// 화면 좌우 기본 여백, 카드 내부 패딩
  static const double md = 16;

  /// 블록 사이, 큰 카드 내부 패딩
  static const double lg = 24;

  /// 섹션 사이
  static const double xl = 32;

  /// 화면 상단 여백, 빈 상태 위아래
  static const double xxl = 48;
}
