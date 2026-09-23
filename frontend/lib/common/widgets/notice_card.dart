import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 안내 카드(datingApp.pen 04-1b `Kakao Search Notice` 강조형 · 04-3 `Avatar Notice` 기본형).
/// 꼭 읽어야 하는 안내는 강조형(분홍 바탕), 곁들이는 설명은 기본형(회색 바탕)이다.
///
/// 2026-09-23: 기본형 치수를 pen 04-3 `dWNkb` 값으로 맞췄다(모서리 12 · 아이콘 14 ·
/// 아이콘-제목 6 · 제목-본문 6 · 본문 줄높이 1.5). 강조형은 04-1b 값 그대로 둔다.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    required this.title,
    required this.body,
    this.icon = AppIcons.circleAlert,
    this.isEmphasis = false,
    this.footer,
    this.child,
    super.key,
  });

  final String title;
  final String body;
  final IconData icon;
  final bool isEmphasis;

  /// 강조형에서 카드 맨 아래에 붙는 작은 보충 설명.
  final String? footer;

  /// 강조형 안에 끼워 넣는 흰 칸(04-1b 의 "아이디로 친구 추가 허용" 줄).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: isEmphasis
          ? const EdgeInsets.all(AppSpacing.md)
          : const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      decoration: BoxDecoration(
        color: isEmphasis ? AppColors.primaryWash : AppColors.surfaceSoft,
        // 기본형 모서리 12 는 토큰 sm(8)·md(14) 사이 pen 실측값이다.
        borderRadius: BorderRadius.circular(isEmphasis ? AppRadius.md : 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: isEmphasis ? 20 : 14,
                color: isEmphasis ? AppColors.primaryText : AppColors.body,
              ),
              SizedBox(width: isEmphasis ? AppSpacing.xs : 6),
              Expanded(child: Text(title, style: _titleStyle)),
            ],
          ),
          SizedBox(height: isEmphasis ? AppSpacing.sm : 6),
          Text(body, style: _bodyStyle),
          if (child != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(10),
              ),
              child: child,
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(footer!, style: AppTypography.caption.copyWith(color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  TextStyle get _titleStyle {
    return isEmphasis
        ? AppTypography.bodyStrong.copyWith(color: AppColors.primaryText, fontWeight: FontWeight.w700)
        : AppTypography.labelSmall.copyWith(color: AppColors.ink);
  }

  TextStyle get _bodyStyle {
    return isEmphasis
        ? AppTypography.bodySmall.copyWith(color: AppColors.body)
        : AppTypography.caption.copyWith(color: AppColors.body, height: 1.5);
  }
}
