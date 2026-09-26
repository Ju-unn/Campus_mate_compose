import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 15d · 17c 가 같이 쓰는 토스트(pen Toast `I8UOWm`). 뜨고 사라지는 시간은 SnackBar 에 맡긴다 — 두 화면에
/// 타이머를 따로 두지 않는다. 보상(15d-3 `NDZnK`)은 글자만 — 재화 하트는 Lucide 로 그리지 않는다(DESIGN §8.10).
void showPollToast(BuildContext context, String message) {
  final isReward = message == pollRewardMessage;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // pen `NDZnK`: 하단 내비 위 16. SnackBar 기본(바깥 아래 10 + 안쪽 위아래 14)을 걷어 낸다.
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      content: Center(
        child: AppToast(
          leading: isReward ? null : const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
          label: message,
        ),
      ),
    ));
}
