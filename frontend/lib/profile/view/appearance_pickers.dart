import 'package:campus_mate/common/widgets/select_chip.dart';
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
    // 8종을 2행×4열로 깐다(datingApp.pen `mpvfQ` 안 `Ryq6H`) — 카드 72×112, 간격 8, 아이콘 위·이름 아래다.
    // 폭을 숫자로 박지 않고 비율로 둔다 — 360dp 기준 실측이라 더 좁은 기기에서는 같이 줄어들어야 한다.
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      childAspectRatio: 72 / 112,
      children: [
        for (final type in AnimalType.values)
          _PickerCell(
            isSelected: selected.contains(type),
            onTap: () => onTap(type),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 카드 폭에 꽉 차는 정사각 그림(pen 72×72, 좌우 여백 없음).
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.asset(type.iconAsset, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                // 4열이라 칸이 좁다 — '햄스터상'까지 한 줄에 들어가는 크기다(종전 label 18sp 는 넘친다).
                Text(type.label, style: AppTypography.labelSmall.copyWith(color: AppColors.ink)),
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
    // pen 은 한 줄에 3개씩 **균등 폭**이다 — 글자 폭으로 재면 '두부상'과 '청순상'의 칸 크기가 달라진다.
    // 마지막 줄의 2개는 남은 폭을 그대로 나눠 가져 더 넓어진다.
    return Column(
      children: [
        for (var start = 0; start < ImpressionType.values.length; start += _perRow) ...[
          if (start > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (var i = start; i < start + _perRow && i < ImpressionType.values.length; i++) ...[
                if (i > start) const SizedBox(width: AppSpacing.xs),
                Expanded(child: _chip(ImpressionType.values[i])),
              ],
            ],
          ),
        ],
      ],
    );
  }

  static const int _perRow = 3;

  /// 회색 채움 + 테두리 없음, 고르면 분홍 워시 + 분홍 테두리 — 04-1 성별·MBTI 칩과 같은 칸이다.
  /// 높이만 다르다(pen `BGMWX` 40, 04-1 `Chip` 35).
  Widget _chip(ImpressionType type) {
    return SelectChip(
      label: type.label,
      isSelected: selected.contains(type),
      onTap: () => onTap(type),
      height: 40,
    );
  }
}

/// 선택 = `{colors.primary}` 1px 테두리 + `{colors.primary-wash}` 채움(DESIGN.md §8.5 "칸 선택" 패턴).
/// 모서리 14 · 미선택 테두리 #EBEBEB(2026-09-26 사용자 확정 — pen 도 이 값으로 맞춘다).
class _PickerCell extends StatelessWidget {
  const _PickerCell({required this.isSelected, required this.onTap, required this.child});

  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 낭독기에 "고름/안 고름"이 들어가야 한다 — 색만으로는 전달되지 않는다(SelectChip 과 같다).
    return Semantics(
      selected: isSelected,
      button: true,
      // 칸도 자기 Material 을 들고 있어야 한다 — 없으면 테두리·채움이 Scaffold 에 칠해져
      // 목록을 당겼다 놓을 때 그림만 움직인다(SelectChip 과 같은 자리, 2026-09-26 실기기).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Ink(
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryWash : AppColors.canvas,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: isSelected ? AppColors.primary : AppColors.hairlineSoft),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
