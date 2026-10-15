import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/view/paid_card_info_sheet.dart';
import 'package:flutter/material.dart';

/// 앱 투어 5단계의 정밀 분석 항목 넷 — 결제 카드 안내 시트("이렇게 정밀하게 골랐어요")의 이름 · 3D 그림을 한 줄씩.
/// 시트의 설명 문장 · 강조 상자("가장 잘 맞는 …")는 옮기지 않는다(투어 문구 규칙).
class TourPrecisionPoints extends StatelessWidget {
  const TourPrecisionPoints({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.xs,
      children: [
        for (final reason in paidCardReasons)
          Row(
            children: [
              Icon3d(reason.icon, size: 24),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(reason.title, style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 1.4))),
            ],
          ),
      ],
    );
  }
}
