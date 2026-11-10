import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 사유 한 줄(pen RadioRow `M7E1k` Off / `SlAif` On, 행 높이 48). 라디오 24 와 글자는 행 세로 가운데.
/// 신고 시트(`yl8gX`)와 문의 사유 시트(`Ywu44`)가 같이 쓴다.
class ReasonRadioRow extends StatelessWidget {
  const ReasonRadioRow({required this.label, required this.isSelected, required this.onTap, super.key});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: isSelected,
      // 눌림 효과가 시트와 같이 움직이게 행 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            // pen RadioRow 높이 48(target.comfortable). 최소값이라 글자를 키우면 행이 따라 커진다.
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _RadioMark(isSelected: isSelected),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      // pen 16 / 500(선택 600), 줄높이 속성 없음 · 렌더 22.
                      style: AppTypography.body.copyWith(
                        color: AppColors.ink,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        height: 22 / 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 라디오 24 원. 끔: 흰 채움 + outline 1.5 / 켬: primary 2 + 가운데 점 12.
class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.canvas,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.outline,
          width: isSelected ? 2 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: isSelected
          ? Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
            )
          : null,
    );
  }
}
