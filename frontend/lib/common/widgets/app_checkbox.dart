import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

/// 체크 칸 24, 모서리 6. 켜짐(pen `ORl5o`) primary 채움 + 흰 체크 16, 꺼짐(`zlg4q`) 흰 채움 + outline 1.5 테두리.
/// 누르는 영역은 칸이 아니라 줄이 가진다 — 칸은 그림만 그린다(지인 차단 8e 줄 · 약관 동의 02-c 줄).
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({required this.checked, super.key});

  final bool checked;

  /// pen 모서리 6 은 라운드 토큰(sm 8)보다 작은 값이다.
  static const double _radius = 6;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      // 가운데 정렬이 없으면 Container 가 체크 아이콘을 24 로 조인다(pen 체크 16).
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked ? AppColors.primary : AppColors.canvas,
        borderRadius: BorderRadius.circular(_radius),
        border: checked ? null : Border.all(color: AppColors.outline, width: 1.5),
      ),
      child: checked ? const Icon(AppIcons.check, size: 16, color: AppColors.onPrimary) : null,
    );
  }
}
