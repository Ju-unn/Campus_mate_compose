import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 고르는 칩(datingApp.pen `Chip` 인스턴스 — 높이 35 · 알약 모서리, 태그 칩 `WzXvK` 도 2026-10-01 부터 알약).
/// 04-1 성별·내 MBTI, 06-1 선호 MBTI 처럼 짧은 낱말을 고르는 자리에 쓴다.
class SelectChip extends StatelessWidget {
  const SelectChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.width,
    this.height = 35,
    this.radius = AppRadius.pill,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// 디자인 파일이 칸 너비를 정해 둔 자리(성별 76, MBTI 48)에만 넘긴다.
  final double? width;

  /// 디자인 파일의 칸 높이. 04-1 `Chip` 은 35, 04-4·06-1 인상 칩(`BGMWX`)은 44 다.
  final double height;

  /// 기본은 알약(pen `WzXvK` 9999). 인상 칩 `BGMWX` 는 개편 여부를 pen 에서 아직 못 봐서 8 을 넘긴다(대장 10-03).
  final double radius;

  /// 글자 좌우 여백. 칸 너비가 정해지지 않은 칩(태그 `WzXvK` 좌우 12)만 넘긴다 —
  /// 너비를 받은 칩(성별 76·MBTI 48)은 글자를 가운데 둘 뿐이라 여백이 없다.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // 낭독기에 "고름/안 고름"이 들어가야 한다 — 색만으로는 전달되지 않는다.
    return Semantics(
      selected: isSelected,
      button: true,
      // `Ink` 는 **가장 가까운 Material** 에 칠한다 — 그게 Scaffold 면 회색 칸이 화면에 눌러앉아,
      // 태그 목록을 당겼다 놓을 때 글자만 따라 움직인다(2026-09-26 실기기). 칩에 자기 Material 을 준다.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          // 칸 크기는 **최소값**이다 — 평소는 pen 값(너비 [width] · 높이 [height], 테두리 포함) 그대로이고, 글자를 키우면
          // (DESIGN §11.2) 글자에 맞춰 늘어난다. 고정 크기로 두면 "모름"(폭 56)이 두 줄로 접혀 잘린다.
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width ?? 0, minHeight: height),
            child: Ink(
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryWash : AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
              ),
              // 칸 너비를 받지 않은 칩은 **글자 폭만큼만** 차지한다 — 늘어나 채우면
              // 줄 폭을 통째로 먹어서 `Wrap` 안에서 칩이 한 줄에 하나씩 쌓인다(2026-09-26 실기기).
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: padding,
                  child: Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.ink)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
