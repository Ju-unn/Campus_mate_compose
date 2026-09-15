import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('press 는 눌림 피드백용 120ms easeOut 이다', () {
    expect(AppMotion.press, const Duration(milliseconds: 120));
    expect(AppMotion.pressCurve, Curves.easeOut);
  });

  test('standard 는 화면 전환용 220ms easeOutCubic 이다', () {
    expect(AppMotion.standard, const Duration(milliseconds: 220));
    expect(AppMotion.standardCurve, Curves.easeOutCubic);
  });

  test('emphasis 는 매칭 성사·카드 등장용 420ms easeOutBack 이다', () {
    expect(AppMotion.emphasis, const Duration(milliseconds: 420));
    expect(AppMotion.emphasisCurve, Curves.easeOutBack);
  });
}
