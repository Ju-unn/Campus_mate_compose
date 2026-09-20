import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';

/// 얼굴상·인상 피커(DESIGN.md §8.5 `animal-type-picker`·`impression-picker`).
/// 04-4(본인, 단일 선택)와 06-1(선호, 최대 3개)이 같은 칸을 쓰므로 여기 한 벌만 둔다.
class AnimalTypePicker extends StatelessWidget {
  const AnimalTypePicker({required this.selected, required this.onTap, super.key});

  final Set<AnimalType> selected;
  final ValueChanged<AnimalType> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      childAspectRatio: 2.4,
      children: [
        for (final type in AnimalType.values)
          _PickerCell(
            isSelected: selected.contains(type),
            onTap: () => onTap(type),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(type.iconAsset, width: 40, height: 40),
                const SizedBox(width: AppSpacing.xxs),
                Text(type.label, style: AppTypography.label.copyWith(color: AppColors.ink)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 인상 5종은 일러스트 없이 한글 라벨 칩만 쓴다(DESIGN.md §8.5 — 선한상과 구분이 안 됐다).
class ImpressionTypePicker extends StatelessWidget {
  const ImpressionTypePicker({required this.selected, required this.onTap, super.key});

  final Set<ImpressionType> selected;
  final ValueChanged<ImpressionType> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final type in ImpressionType.values)
          FilterChip(
            label: Text(type.label),
            selected: selected.contains(type),
            onSelected: (_) => onTap(type),
          ),
      ],
    );
  }
}

/// 선택 = `{colors.primary}` 1px 테두리 + `{colors.primary-wash}` 채움(DESIGN.md §8.5 "칸 선택" 패턴).
class _PickerCell extends StatelessWidget {
  const _PickerCell({required this.isSelected, required this.onTap, required this.child});

  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Ink(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryWash : AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.hairline),
        ),
        child: Center(child: child),
      ),
    );
  }
}
