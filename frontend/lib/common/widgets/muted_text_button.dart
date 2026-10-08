import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 관문 화면의 조용한 글자 버튼(pen `u05wB`) — 14/600 muted, 최소 높이 48.
/// 02-c · 02 의 "로그아웃", 03 의 "다른 학교 메일 입력" 이 같은 모양을 쓴다.
class MutedTextButton extends StatelessWidget {
  const MutedTextButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        // 높이는 최소값만 건다 — 글자를 키우면 버튼이 따라 커진다.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            // pen `u05wB` 14/600, 줄높이 속성 없음 · 렌더 20.
            child: Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.muted, height: 20 / 14)),
          ),
        ),
      ),
    );
  }
}
