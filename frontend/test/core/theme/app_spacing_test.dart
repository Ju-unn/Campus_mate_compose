import 'package:campus_mate/core/theme/app_spacing.dart';
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
}
