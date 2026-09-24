import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 하단 버튼 위에 잠깐 뜨는 알림 띠(datingApp.pen `Toast` 마스터 — 04-3 `wQBW0` · 04-2 `I8UOWm`).
///
/// 앞에 오는 16 짜리 그림만 화면마다 다르다(04-3 은 도는 표시, 04-2 는 경고 아이콘).
class AppToast extends StatelessWidget {
  const AppToast({required this.leading, required this.label, super.key});

  /// 16×16 자리에 들어가는 그림.
  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    // 화면에 잠깐 떴다 사라져 초점을 받을 일이 없다 — liveRegion 이라야 TalkBack 이 바로 읽어 준다.
    return Semantics(
      liveRegion: true,
      child: Container(
        // pen 실측 세로 10. 간격 토큰 xs(8)·sm(12) 사이 값이라 토큰으로 갈음하지 않는다.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceInk,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 16, height: 16, child: leading),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.onInk)),
          ],
        ),
      ),
    );
  }
}
