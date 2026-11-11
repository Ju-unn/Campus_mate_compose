import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// 시트 맨 위 손잡이(pen `L3Bec` · `Y1P837` · `k8GZO` · `R5hkR` · `w8UdMw` · `vH016`) — 36×4 hairline 모서리 8.
/// 높이가 4 라 모서리 2 · 8 · 알약이 보기엔 같아 하나로 합쳤다. 위아래 여백은 주지 않는다(시트마다 다르다 — 호출쪽 몫).
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.hairline,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}
