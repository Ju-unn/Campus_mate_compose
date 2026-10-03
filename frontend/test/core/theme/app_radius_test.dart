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

  test('버튼 라운드는 pen Button `HE8FZ` 14 다(2026-10-01 개편, 옛 16)', () {
    expect(AppRadius.button, 14);
  });

  test('입력칸 라운드는 pen `TDM1r` 12, 카드 라운드는 pen Card `GvbBr` 16 이다(2026-10-01 개편)', () {
    expect(AppRadius.input, 12);
    expect(AppRadius.card, 16);
  });
}
