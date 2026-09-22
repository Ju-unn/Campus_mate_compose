import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 신뢰 확인 시트(화면 14f, pen `p0XJA6` / 시트 `I5GLb`).
/// 매칭 24시간 뒤부터 **방에 들어올 때마다** 뜨고, 스와이프로 닫을 수 있다(강제가 아니다).
class TrustGateSheet extends StatelessWidget {
  const TrustGateSheet({required this.deadlineAt, required this.onAccept, required this.onLeave,
      super.key});

  final DateTime deadlineAt;
  final VoidCallback onAccept;

  /// **거절이 아니라 나가기다**(결정 11). 시트 전용 거절 경로를 만들지 않는다.
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '카카오톡 아이디를 공유할까요?',
              style: AppTypography.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '둘 다 수락하면 카카오톡 아이디와 실제 사진이 서로 공개돼요. '
              '응답 기한 안에 둘 다 수락하지 않으면 이 대화는 종료돼요.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            _Countdown(deadlineAt: deadlineAt),
            const SizedBox(height: AppSpacing.md),
            const NoticeCard(
              title: '카카오톡 아이디로 친구 추가 허용',
              body: "카카오톡에서 '아이디로 친구 추가 허용'이 꺼져 있으면 수락해도 연락이 닿지 않아요.",
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: '수락하고 공유하기', onPressed: onAccept),
            const SizedBox(height: AppSpacing.xxs),
            // pen 라벨은 "거절하기" 였다. 거절이 곧 나가기가 되면서 라벨이 그 사실을 말해야 한다(결정 11).
            AppButton(label: '거절하고 나가기', onPressed: onLeave, variant: AppButtonVariant.text),
          ],
        ),
      ),
    );
  }
}

/// 응답 기한 카운트다운(pen `etT0Q`). 남은 시간은 `matches.created_at + 48시간` 에서 뺀다.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.deadlineAt});

  final DateTime deadlineAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.timer, size: 18, color: AppColors.primaryText),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '응답 기한까지',
              style: AppTypography.labelSmall.copyWith(color: AppColors.ink),
            ),
          ),
          CountdownBuilder(
            deadlineAt: deadlineAt,
            builder: (context, remaining) => Text(
              countdownLabel(remaining),
              style: AppTypography.subtitle
                  .copyWith(color: AppColors.primaryText, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
