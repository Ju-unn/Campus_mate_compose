import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 매칭 성사(DESIGN.md 화면 12, pen `UFNSi`).
/// "대화 시작하기" 는 이제 그 방으로 바로 들어간다(조각 5).
/// 들어올 때 마스코트가 0.92 → 1 로 커지며 나타나고(emphasis 420ms, 커브는 크기에만), 120ms 뒤 제목 · 부제가 아래 12 에서
/// 올라온다(standard) — DESIGN §7 의 하루 두 번 emphasis 중 하나. 버튼은 움직이지 않아 처음부터 누를 수 있다.
class MatchMadeScreen extends StatelessWidget {
  const MatchMadeScreen({required this.nickname, this.matchId, super.key});

  final String nickname;

  /// 방 id. 없으면 목록으로 보낸다 — 어느 방인지 모른 채로 방을 열 수는 없다.
  final String? matchId;

  /// 마스코트 뒤 글이 나오는 간격(대장 지시 — 모션 기회 1, pen 에 없는 값)
  static const Duration _textDelay = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Entrance(
                scaleFrom: 0.92,
                duration: AppMotion.emphasis,
                curve: AppMotion.emphasisCurve,
                child: Image.asset('assets/images/mascot-female-reward.png', width: 120),
              ),
              const SizedBox(height: AppSpacing.lg),
              Entrance(
                rise: 12,
                delay: _textDelay,
                child: Column(
                  children: [
                    Text('매칭됐어요!', style: AppTypography.headline.copyWith(color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '$nickname 님과 매칭됐어요.\n대화를 시작해 보세요.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              AppButton(
                label: '대화 시작하기',
                onPressed: () => context.go(
                  matchId == null ? AppRoutes.conversations : '${AppRoutes.chatRoom}/$matchId',
                ),
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
