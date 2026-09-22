import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 시스템 줄(pen `CbXi6`). 나가기(결정 7)와 신뢰 확인 수락(결정 10)이 이 모양으로 남는다.
/// **말풍선이 아니고 아바타도 없다** — 누가 한 말이 아니라 방에서 일어난 일이다.
class SystemMessage extends StatelessWidget {
  const SystemMessage({required this.body, super.key});

  /// 서버가 문장을 통째로 만들어 준다. 앱은 조립하지 않는다 —
  /// 그래야 닉네임을 바꿔도 옛 줄이 그때의 이름을 그대로 간직한다.
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceStrong,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.muted),
        ),
      ),
    );
  }
}
