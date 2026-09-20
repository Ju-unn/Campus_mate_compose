import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 온보딩 진행 점(datingApp.pen `Progress Dots · 6` · `· 3`).
/// 8×8 점을 8 간격으로 늘어놓고 현재 단계만 강조색으로 칠한다.
class ProgressDots extends StatelessWidget {
  const ProgressDots({required this.current, required this.total, super.key});

  /// 0부터 센 현재 단계.
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < total; index++)
          Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(left: index == 0 ? 0 : 8),
            decoration: BoxDecoration(
              color: index == current ? AppColors.primary : AppColors.hairline,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}
