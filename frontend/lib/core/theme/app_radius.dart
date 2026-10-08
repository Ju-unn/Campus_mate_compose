/// 라운드 토큰 (DESIGN.md §5.1). 위젯은 이 상수만 읽는다.
///
/// `circle`(아바타, 아이콘 버튼)은 고정 dp 값이 아니라 위젯 크기의 50% 이므로
/// 별도 상수 없이 위젯에서 `BoxShape.circle` 을 직접 쓴다 (2026-09-15 사용자 결정).
abstract final class AppRadius {
  /// 버튼, 입력 필드, 태그 칩
  static const double sm = 8;

  /// 리스트 카드, 수락 대기 행, 채팅 말풍선
  static const double md = 14;

  /// 오늘의 카드, 바텀시트 상단
  static const double lg = 24;

  /// 메인 히어로 배너
  static const double xl = 32;

  /// 필터 칩, MBTI 토글, 카운트 뱃지, 인증 뱃지
  static const double pill = 9999;

  /// 52dp 채움 버튼 전용 (pen Button `HE8FZ`, 2026-10-01 개편 — 옛 56 · 16 은 DESIGN.md §13-107)
  static const double button = 14;

  /// 입력칸 · 고르기칸 · 검색칸 (pen `TDM1r` · `DNyay` · `UtJrJ` · `y7Qlw`, 2026-10-01 개편)
  static const double input = 12;

  /// 카드 (pen Card `GvbBr` · Card · Outline `sPWwm`, 2026-10-01 개편)
  static const double card = 16;

  /// 시작 화면 소셜 로그인 버튼(46 높이, 대장 지시문 07 규칙표 값). [input] 과 값은 같지만 근거가 달라 따로 둔다.
  static const double socialButton = 12;
}
