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
}
