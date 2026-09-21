import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 매칭 성사(DESIGN.md 화면 12, pen `UFNSi`). 채팅방은 조각 5 라 "대화 시작"은
/// 대화 목록(13)으로 보낸다 — 아직 방이 없다.
class MatchMadeScreen extends StatelessWidget {
  const MatchMadeScreen({required this.nickname, super.key});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/mascot-female-reward.png', width: 120),
              const SizedBox(height: AppSpacing.lg),
              Text('매칭됐어요!', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '$nickname 님도 수락했어요.\n대화를 시작해 보세요.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 40),
              AppButton(
                label: '대화 시작하기',
                onPressed: () => context.go(AppRoutes.conversations),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: '나중에 확인하기',
                variant: AppButtonVariant.text,
                onPressed: () => context.go(AppRoutes.today),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
