import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('countdown 은 시스템에서 가장 큰 48/700 이다', () {
    expect(AppTypography.countdown.fontSize, 48);
    expect(AppTypography.countdown.fontWeight, FontWeight.w700);
  });

  test('navTitle 은 앱바 제목용 20/700 이다 (2026-09-14 §13-99 해결)', () {
    expect(AppTypography.navTitle.fontSize, 20);
    expect(AppTypography.navTitle.fontWeight, FontWeight.w700);
  });

  test('title 은 카드 이름·나이용 20/600 이다', () {
    expect(AppTypography.title.fontSize, 20);
    expect(AppTypography.title.fontWeight, FontWeight.w600);
  });

  test('body 는 본문 기본 16/400 이다', () {
    expect(AppTypography.body.fontSize, 16);
    expect(AppTypography.body.fontWeight, FontWeight.w400);
  });

  test('label 은 전체 폭 버튼 라벨용 18/700 이다', () {
    expect(AppTypography.label.fontSize, 18);
    expect(AppTypography.label.fontWeight, FontWeight.w700);
  });

  test('badge 는 가장 작은 11/600 이다', () {
    expect(AppTypography.badge.fontSize, 11);
    expect(AppTypography.badge.fontWeight, FontWeight.w600);
  });

  test('모든 스타일은 Pretendard 폰트를 쓴다', () {
    for (final style in AppTypography.values) {
      expect(style.fontFamily, 'Pretendard');
    }
  });
}
