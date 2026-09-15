import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('라운드 토큰은 DESIGN.md §5.1 확정값을 쓴다', () {
    expect(AppRadius.sm, 8);
    expect(AppRadius.md, 14);
    expect(AppRadius.lg, 24);
    expect(AppRadius.xl, 32);
    expect(AppRadius.pill, 9999);
  });

  test('버튼 라운드는 DESIGN.md §8.3 토스 비례값(16)을 쓴다', () {
    expect(AppRadius.button, 16);
  });
}
