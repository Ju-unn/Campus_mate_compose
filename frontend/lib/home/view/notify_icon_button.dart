import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 앱바 알림 종(pen Z54et `IconButton · Notify` `stzJJ`). 48 터치 칸 안에 22 종,
/// 숫자 배지는 종 상자 기준 (12, -4) 에 흰 테두리 1.5 로 얹는다.
/// 알림 화면이 아직 없어 누를 곳은 두지 않는다.
class NotifyIconButton extends StatelessWidget {
  const NotifyIconButton({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: count > 0 ? '알림 $count개' : '알림',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: SizedBox.square(
              dimension: 24,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(child: Icon(AppIcons.bell, size: 22, color: AppColors.muted)),
                  if (count > 0)
                    Positioned(
                      left: 12,
                      top: -4,
                      // pen 16 은 최소 크기다 — 글자를 키우면 배지도 같이 커진다(DESIGN §11.2).
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: AppColors.canvas, width: 1.5),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: AppTypography.badge.copyWith(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
