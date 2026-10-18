/// 웹 전용 간격 · 모서리 · 크기 토큰. 표의 값은 pen 웹 값표(대장 전달 — 노드 id 미확인)이고, 앱 토큰
/// (frontend/lib/core/theme/app_spacing.dart · app_radius.dart) 10-18 사본에서 시작했다. 앱 토큰과 따로 바뀐다.
abstract final class AdminSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// 관문 카드(A0 CRAiQ · A1 X83GPt · AzU1n) 안쪽 4면 40 — campus-pen 재조회(10-18).
  static const double gateCard = 40;

  /// A1 등록(X83GPt) · 입력(AzU1n) 카드 안 덩어리 사이 20 — campus-pen 재조회. A0 는 24([lg]).
  static const double gateBlock = 20;

  /// 아이콘 · 제목이 가운데 놓인 카드(권한 없음 · 2단계 필요)의 제목 → 설명 — PNG 측정 14.
  static const double statusTitleToBody = 14;

  /// SideNav 로고 묶음 → 첫 메뉴 — PNG 측정(첫 메뉴 y 96).
  static const double sideNavHeaderGap = 24;
}

abstract final class AdminRadius {
  /// 단추 · 입력칸 · 메뉴 항목 · 코드 칸 · 비밀 키 상자
  static const double sm = 8;

  /// 카드
  static const double md = 14;

  static const double lg = 24;

  /// 배지
  static const double pill = 9999;
}

abstract final class AdminSizes {
  /// 단추 · 입력칸 · 메뉴 항목 높이
  static const double control = 44;

  /// 칩(다음 조각)
  static const double chip = 36;

  static const double sideNavWidth = 240;
  static const double topBarHeight = 64;

  /// 데스크톱 기준 1440, 이보다 좁으면 가로 스크롤(설계서 §9)
  static const double minWindowWidth = 1280;

  /// 메뉴 아이콘 · 코드 칸(PNG 측정)
  static const double navIcon = 20;
  static const double codeCellWidth = 52;
  static const double codeCellHeight = 60;

  /// 권한 없음 · 2단계 필요 아이콘(PNG 측정 40), 오류 줄 아이콘 16, 배지 점 8
  static const double statusIcon = 40;
  static const double errorIcon = 16;
  static const double badgeDot = 8;
}
