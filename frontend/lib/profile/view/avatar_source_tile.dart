import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 아바타 원본 사진 한 칸(pen `sg7X8` PhotoSlot · AvatarSource, 158×158). 가입 04-3 과 나 탭 15b-4/15b-5 가 같이 쓴다.
/// 고른 칸은 빨간 테두리(안쪽 3px #FF385C)와 왼쪽 위 "아바타로 선택" 배지, 안 고른 칸은 사진만.
/// 크기는 부모가 정한다(보통 158×158 — 04-3 은 두 칸을 나란히 놓는다).
class AvatarSourceTile extends StatelessWidget {
  const AvatarSourceTile({required this.image, required this.isSelected, required this.onTap, super.key});

  final ImageProvider image;
  final bool isSelected;

  /// null 이면 누를 수 없다(올리는 중).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          foregroundDecoration: isSelected
              ? BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 3),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                )
              : null,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Stack(
            children: [
              Positioned.fill(child: Image(image: image, fit: BoxFit.cover)),
              if (isSelected)
                Positioned(
                  left: AppSpacing.xs,
                  top: AppSpacing.xs,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(AppIcons.check, size: 12, color: AppColors.onPrimary),
                        const SizedBox(width: AppSpacing.xxs),
                        Text('아바타로 선택', style: AppTypography.badge.copyWith(color: AppColors.onPrimary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
