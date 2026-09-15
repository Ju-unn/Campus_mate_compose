import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('브랜드 색은 DESIGN.md §2.1 확정값을 쓴다', () {
    expect(AppColors.primary, const Color(0xFFFF385C));
    expect(AppColors.primaryPressed, const Color(0xFFE00B41));
    expect(AppColors.primaryText, const Color(0xFFC4224B));
    expect(AppColors.primaryWash, const Color(0xFFFFF0F2));
    expect(AppColors.onPrimary, const Color(0xFFFFFFFF));
  });

  test('비활성 채움색은 무채색 채움과 같은 값을 쓴다 (2026-09-15 결정)', () {
    expect(AppColors.primaryDisabled, const Color(0xFFE5E5E5));
  });

  test('표면색은 DESIGN.md §2.2 확정값을 쓴다', () {
    expect(AppColors.canvas, const Color(0xFFFFFFFF));
    expect(AppColors.surfaceSoft, const Color(0xFFF7F7F7));
    expect(AppColors.surfaceStrong, const Color(0xFFF2F2F2));
    expect(AppColors.surfaceInk, const Color(0xFF222222));
    expect(AppColors.scrim, Colors.black.withValues(alpha: 0.5));
  });

  test('텍스트 색은 DESIGN.md §2.3 확정값을 쓴다', () {
    expect(AppColors.ink, const Color(0xFF222222));
    expect(AppColors.body, const Color(0xFF3F3F3F));
    expect(AppColors.muted, const Color(0xFF6A6A6A));
    expect(AppColors.disabled, const Color(0xFF929292));
    expect(AppColors.onInk, const Color(0xFFFFFFFF));
  });

  test('경계선 색은 DESIGN.md §2.4 확정값을 쓴다', () {
    expect(AppColors.hairline, const Color(0xFFDDDDDD));
    expect(AppColors.hairlineSoft, const Color(0xFFEBEBEB));
    expect(AppColors.outline, const Color(0xFF767676));
  });

  test('의미색은 DESIGN.md §2.5 확정값을 쓴다', () {
    expect(AppColors.error, const Color(0xFFC13515));
    expect(AppColors.success, const Color(0xFF25795A));
  });
}
