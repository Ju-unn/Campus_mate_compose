import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';

/// 종교 고르기(DESIGN.md §8.5 religion-select, pen `KT7Lu`) — 2×2 칸, 높이 56, 칸 사이 12.
/// 05-10(성향 설문)과 15-6 기본 정보 수정이 같이 쓴다. 질문 제목 · 라벨은 화면 쪽이 둔다.
class ReligionPicker extends StatelessWidget {
  const ReligionPicker({required this.selected, required this.onSelected, super.key});

  final Religion? selected;
  final ValueChanged<Religion> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      mainAxisExtent: 56,
      children: [
        for (final religion in Religion.values)
          ChoiceCell(
            label: religion.label,
            isSelected: selected == religion,
            onTap: () => onSelected(religion),
          ),
      ],
    );
  }
}

/// 흡연 고르기(DESIGN.md §8.5 smoke-toggle, pen `juWlH`) — 한다 / 안 한다 두 칸, 높이 56, 칸 사이 12.
/// [isSmoker] null 은 아직 안 고른 것이다.
class SmokePicker extends StatelessWidget {
  const SmokePicker({required this.isSmoker, required this.onSelected, super.key});

  final bool? isSmoker;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: ChoiceCell(label: '한다', isSelected: isSmoker == true, onTap: () => onSelected(true)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ChoiceCell(label: '안 한다', isSelected: isSmoker == false, onTap: () => onSelected(false)),
          ),
        ],
      ),
    );
  }
}

/// 종교·흡연 공통 "칸 선택"(DESIGN.md §8.5 religion-select·smoke-toggle).
/// 비선택 채움은 표면 회색이다(pen `Rmfti`·`Y1TDq2` 2026-09-26 수정) —
/// 종전 `primaryDisabled`(#E5E5E5)는 **비활성 채움** 토큰이라, 고를 수 있는 칸이 꺼진 버튼처럼 보였다.
class ChoiceCell extends StatelessWidget {
  const ChoiceCell({required this.label, required this.isSelected, required this.onTap, super.key});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 칸이 자기 Material 을 들고 있어야 채움이 Scaffold 에 칠해지지 않는다(select_chip.dart 와 같다).
    // 낭독기에 "고름/안 고름"이 들어가야 한다 — 색만으로는 전달되지 않는다.
    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Ink(
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryWash : AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
            ),
            child: Center(
              child: Text(label, style: AppTypography.label.copyWith(color: AppColors.ink)),
            ),
          ),
        ),
      ),
    );
  }
}
