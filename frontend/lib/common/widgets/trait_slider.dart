import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 성향 설문 슬라이더(datingApp.pen `TraitSlider`).
/// 5단계를 점으로 고르고 숫자는 보여주지 않는다(DESIGN.md §6.2 -1/-0.5/0/0.5/1).
/// 고르는 길은 셋이다(DESIGN §8.5 "탭 또는 드래그(5칸 스냅)"): 점 누르기 · 가로로 끌기(손가락에 가장 가까운 칸으로 붙는다) ·
/// 낭독기의 올리기/내리기. 설문 PageView 는 손으로 넘기지 않게 막혀 있어(NeverScrollable) 가로 끌기와 다투지 않는다.
class TraitSlider extends StatelessWidget {
  const TraitSlider({
    required this.value,
    required this.onChanged,
    required this.leftLabel,
    required this.rightLabel,
    super.key,
  });

  static const List<double> steps = [-1, -0.5, 0, 0.5, 1];

  /// 아직 고르지 않았으면 null — 어떤 점도 강조하지 않는다.
  final double? value;
  final ValueChanged<double> onChanged;
  final String leftLabel;
  final String rightLabel;

  @override
  Widget build(BuildContext context) {
    // 낭독기에는 점 다섯 개 · 양 끝 글자를 따로 내놓지 않고 슬라이더 하나로 읽힌다(양 끝 글자는 이름에 들어 있다).
    return _semantics(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _track(),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(leftLabel, style: AppTypography.caption.copyWith(color: AppColors.muted)),
              Text(rightLabel, style: AppTypography.caption.copyWith(color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  /// 고르지 않은 상태(null)에서 올리기 · 내리기는 가운데에서 한 칸 옮긴 자리다.
  Widget _semantics(Widget child) {
    final index = value == null ? null : steps.indexOf(value!);
    final from = index ?? steps.length ~/ 2;
    final up = from + 1 < steps.length ? from + 1 : null;
    final down = from > 0 ? from - 1 : null;
    return Semantics(
      slider: true,
      excludeSemantics: true,
      label: '$leftLabel부터 $rightLabel까지',
      value: index == null ? '고르지 않음' : _stepLabel(index),
      increasedValue: up == null ? null : _stepLabel(up),
      decreasedValue: down == null ? null : _stepLabel(down),
      onIncrease: up == null ? null : () => onChanged(steps[up]),
      onDecrease: down == null ? null : () => onChanged(steps[down]),
      child: child,
    );
  }

  /// 숫자 값(-1 ~ 1)은 화면에 안 보이는 값이라 낭독기에도 몇째 칸인지만 읽는다.
  String _stepLabel(int index) => '${steps.length}단계 중 ${index + 1}단계';

  Widget _track() {
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onHorizontalDragStart: (details) => _dragTo(details.localPosition.dx, constraints.maxWidth),
        onHorizontalDragUpdate: (details) => _dragTo(details.localPosition.dx, constraints.maxWidth),
        // 눈에 보이는 트랙은 22 높이지만, 손가락이 닿는 칸은 44 로 잡는다(DESIGN.md §5.3 최소 44×44).
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(height: 2, color: AppColors.hairline),
              Row(
                children: [
                  for (final step in steps)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(step),
                        child: Center(child: _dot(isSelected: value == step)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 점마다 같은 폭의 칸이라, 손가락이 든 칸의 점이 곧 가장 가까운 점이다. 트랙 밖으로 나가면 끝 칸에 머문다.
  void _dragTo(double dx, double width) {
    final index = (dx / (width / steps.length)).floor().clamp(0, steps.length - 1);
    if (steps[index] != value) {
      onChanged(steps[index]);
    }
  }

  Widget _dot({required bool isSelected}) {
    // pen `mkf89` 값(2026-09-26 erd3 수정). 종전 12/18 은 실기기에서 어디를 골랐는지 잘 안 보였다.
    final size = isSelected ? 28.0 : 18.0;
    // 안 고른 점은 흰 속 + outline 테두리(2026-10-15) — hairline 채움은 흰 바탕에서 1.3:1 이라 비텍스트 대비 3:1 미달.
    // 선 두께 1.5 는 AppCheckbox 꺼짐 테두리와 같은 값(pen 확인 필요: 1.5~2).
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.canvas,
        border: isSelected ? null : Border.all(color: AppColors.outline, width: 1.5),
        shape: BoxShape.circle,
      ),
    );
  }
}
