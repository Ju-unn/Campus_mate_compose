import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 졸업생 관문 화면(방법 고르기 · 신청 폼 · 02)이 실패를 알리는 토스트(pen Toast `I8UOWm` — 경고 아이콘 16 + 글자).
/// 오류 문구는 뷰모델이 한 번만 붙여 주므로 화면이 `ref.listen` 으로 이것을 부른다. 시간은 SnackBar 기본에 맡긴다.
void showGateToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        // SnackBar 기본(바깥 아래 10 + 안쪽 위아래 14)을 걷어 내야 화면 아래 16 이다(poll_toast.dart 와 같다).
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        content: Center(
          child: AppToast(
            leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
            label: message,
          ),
        ),
      ),
    );
}
