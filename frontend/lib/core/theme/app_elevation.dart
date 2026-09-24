import 'package:flutter/material.dart';

/// 그림자 토큰 (DESIGN.md §6). 그림자는 한 단계만 존재한다.
///
/// Flutter 기본 `Card.elevation` 을 쓰면 이 규칙이 깨지므로,
/// 오늘 탭 요약 카드·잠금 카드, 그리고 04-2 에서 길게 눌러 끄는 사진 칸에만
/// [card] 로 `BoxShadow` 를 직접 지정한다(끌린 칸이 떠 보여야 어디로 가는지 알 수 있다).
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
}
