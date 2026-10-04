import 'package:flutter/material.dart';

/// 그림자 토큰 (DESIGN.md §6). 2026-10-01 개편으로 자리마다 세기가 갈렸다 — 화면은 아래 이름 중 하나를 고른다.
///
/// Flutter 기본 `Card.elevation` 을 쓰면 이 규칙이 깨지므로,
/// 그림자가 필요한 자리만 아래 이름으로 `BoxShadow` 를 직접 지정한다.
/// [card] 는 04-2 에서 길게 눌러 끄는 사진 칸(끌린 칸이 떠 보여야 어디로 가는지 알 수 있다)과
/// 15-5 기본 정보 카드(`N1dIuc`) 두 곳이다. 오늘 탭 요약 카드는 [cardSoft], 화면 15 · 15-5 의
/// ProfileEntryRow(pen `fN0xc`)는 [row] 로 옮겼다(2026-10-01 개편).
/// 나머지 표면(앱바·리스트·입력·버튼·바텀 내비)은 그림자 없이 평면으로 둔다.
abstract final class AppElevation {
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F1A1619),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
    BoxShadow(
      color: Color(0x141A1619),
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
  ];

  /// 오늘의 카드 요약 · 잠금 카드 (pen `v26S7z` · `BpP33`, 2026-10-01 완화 — 두 겹 구조는 [card] 와 같고 옅다)
  static const List<BoxShadow> cardSoft = <BoxShadow>[
    BoxShadow(color: Color(0x0A1A1619), offset: Offset(0, 2), blurRadius: 8),
    BoxShadow(color: Color(0x0F1A1619), offset: Offset(0, 8), blurRadius: 20),
  ];

  /// 말풍선 메뉴 (pen Popover · Bubble Menu `afUag`, 2026-10-01 한 겹으로)
  static const List<BoxShadow> popover = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), offset: Offset(0, 4), blurRadius: 12),
  ];

  /// 목록 행 (pen ProfileEntryRow `fN0xc`, 2026-10-01 한 겹으로)
  static const List<BoxShadow> row = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 6),
  ];

  /// 성향 막대 (pen TraitProgressBar `IHitX`, 2026-10-01 추가)
  static const List<BoxShadow> trait = <BoxShadow>[
    BoxShadow(color: Color(0x1C745C78), offset: Offset(0, 1), blurRadius: 4),
  ];

  /// 모집 배지 (pen Goal Badge `R6EEu` · `RKJv5`, 2026-10-01 추가)
  static const List<BoxShadow> badge = <BoxShadow>[
    BoxShadow(color: Color(0x1A6F4055), offset: Offset(0, 2), blurRadius: 10),
  ];

  /// 화면 아래에 붙은 시트 · 바가 위로 드리우는 그림자 — #00000026 (0,-2) blur 16.
  /// 투표 · 지인 리뷰 시트, 친구 초대 시트가 같은 리터럴을 따로 갖고 있던 것을 모았다(백로그 76).
  static const List<BoxShadow> top = <BoxShadow>[
    BoxShadow(color: Color(0x26000000), offset: Offset(0, -2), blurRadius: 16),
  ];
}
