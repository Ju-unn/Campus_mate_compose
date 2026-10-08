import 'package:campus_mate/core/auth/confirm_sign_out.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 관문 화면 맨 아래의 "로그아웃" 글자 버튼. 약관 동의(02-c, pen `u05wB`)와 학교 메일 입력(02)이 같은 모양 ·
/// 같은 동작(16g 확인 시트 → [confirmSignOut])을 쓴다. 소셜로 잘못 들어온 사람의 탈출구다.
class LogoutTextButton extends ConsumerWidget {
  const LogoutTextButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => confirmSignOut(context, ref),
        // 높이는 최소값만 건다 — 글자를 키우면 버튼이 따라 커진다.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            // pen `u05wB` 14/600, 줄높이 속성 없음 · 렌더 20.
            child: Text('로그아웃', style: AppTypography.labelSmall.copyWith(color: AppColors.muted, height: 20 / 14)),
          ),
        ),
      ),
    );
  }
}
