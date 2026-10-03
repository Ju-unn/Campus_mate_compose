import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('카드 그림자는 DESIGN.md §6 확정 두 겹이다', () {
    expect(AppElevation.card, hasLength(2));

    final near = AppElevation.card[0];
    expect(near.color, const Color(0x0F1A1619));
    expect(near.offset, const Offset(0, 2));
    expect(near.blurRadius, 8);

    final far = AppElevation.card[1];
    expect(far.color, const Color(0x141A1619));
    expect(far.offset, const Offset(0, 8));
    expect(far.blurRadius, 24);
  });

  test('오늘의 카드 요약 · 잠금 카드 그림자는 card 보다 옅은 두 겹이다 — pen `v26S7z` · `BpP33`(2026-10-01)', () {
    expect(AppElevation.cardSoft, const <BoxShadow>[
      BoxShadow(color: Color(0x0A1A1619), offset: Offset(0, 2), blurRadius: 8),
      BoxShadow(color: Color(0x0F1A1619), offset: Offset(0, 8), blurRadius: 20),
    ]);
  });

  test('말풍선 메뉴 그림자는 한 겹이다 — pen Popover · Bubble Menu `afUag`(2026-10-01)', () {
    expect(AppElevation.popover, const <BoxShadow>[
      BoxShadow(color: Color(0x1F000000), offset: Offset(0, 4), blurRadius: 12),
    ]);
  });

  test('목록 행 그림자는 한 겹이다 — pen ProfileEntryRow `fN0xc`(2026-10-01)', () {
    expect(AppElevation.row, const <BoxShadow>[
      BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 6),
    ]);
  });

  test('성향 막대 그림자 — pen TraitProgressBar `IHitX`(2026-10-01)', () {
    expect(AppElevation.trait, const <BoxShadow>[
      BoxShadow(color: Color(0x1C745C78), offset: Offset(0, 1), blurRadius: 4),
    ]);
  });

  test('모집 배지 그림자 — pen Goal Badge `R6EEu` · `RKJv5`(2026-10-01)', () {
    expect(AppElevation.badge, const <BoxShadow>[
      BoxShadow(color: Color(0x1A6F4055), offset: Offset(0, 2), blurRadius: 10),
    ]);
  });
}
