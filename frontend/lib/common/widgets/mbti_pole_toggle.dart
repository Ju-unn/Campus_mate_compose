import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// MBTI 극 칩 묶음(datingApp.pen `Chip` 인스턴스 — 48 너비 · 알약 모서리).
/// 04-1 "내 MBTI"와 06-1 "선호하는 성향(MBTI)"이 같이 쓴다.
/// 축마다 하나만 켤지 여러 개를 켤지는 화면 쪽 규칙이고, 여기서는 칩만 그린다.
class MbtiPoleToggle extends StatelessWidget {
  const MbtiPoleToggle({
    required this.selected,
    required this.onTap,
    this.poles = allPoles,
    this.unknownLabel,
    this.isUnknownSelected = false,
    this.onUnknownTap,
    super.key,
  });

  static const List<String> allPoles = ['E', 'I', 'N', 'S', 'T', 'F', 'J', 'P'];

  /// 디자인 파일은 한 줄에 네 칸씩 끊어 놓는다.
  static const int _polesPerRow = 4;

  final List<String> poles;
  final Set<String> selected;
  final ValueChanged<String> onTap;

  /// 04-1 처럼 "모름" 칸이 필요한 화면만 넘긴다.
  final String? unknownLabel;
  final bool isUnknownSelected;
  final VoidCallback? onUnknownTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var start = 0; start < poles.length; start += _polesPerRow) ...[
          if (start > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (final pole in poles.skip(start).take(_polesPerRow))
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: SelectChip(
                    label: pole,
                    width: 48,
                    radius: AppRadius.pill,
                    isSelected: selected.contains(pole),
                    onTap: () => onTap(pole),
                  ),
                ),
            ],
          ),
        ],
        if (unknownLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          SelectChip(
            label: unknownLabel!,
            width: 56,
            radius: AppRadius.pill,
            isSelected: isUnknownSelected,
            onTap: onUnknownTap ?? () {},
          ),
        ],
      ],
    );
  }
}
