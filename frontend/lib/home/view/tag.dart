import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 읽기만 하는 태그(pen Z54et `Tag` `nAfU0` — 높이 28 · 알약 · 좌우 11).
/// 고르는 칩 `SelectChip`(높이 35)과 다르다.
class Tag extends StatelessWidget {
  const Tag({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    // pen 높이 28 은 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      // `alignment` 을 쓰면 Wrap 안에서 폭을 다 먹는다 — 글자 폭만큼만 차지하게 한다.
      child: Center(
        widthFactor: 1,
        child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.body)),
      ),
    );
  }
}
