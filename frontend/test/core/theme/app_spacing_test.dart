import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('간격 토큰 7종은 DESIGN.md §4.1 확정값을 쓴다', () {
    expect(AppSpacing.xxs, 4);
    expect(AppSpacing.xs, 8);
    expect(AppSpacing.sm, 12);
    expect(AppSpacing.md, 16);
    expect(AppSpacing.lg, 24);
    expect(AppSpacing.xl, 32);
    expect(AppSpacing.xxl, 48);
  });

  test('카드 안쪽은 pen Card `GvbBr` 20 이다(2026-10-01 개편)', () {
    expect(AppSpacing.card, 20);
  });

  test('화면 아래 CTA 바 안쪽은 pen Bottom Bar CTA `A8INC6` [8,24,8,24] 다(2026-10-01 개편, 옛 위 16 · 아래 28)', () {
    expect(AppSpacing.bottomCta, const EdgeInsets.fromLTRB(24, 8, 24, 8));
  });
}
