import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 신청 폼(02-g · 02-g-3) · 02(방법 고르기를 거쳐 온 경우)의 앱바 — pen AppBar · Sub `KH1hX` 에서 제목을 끈 것(`zQjoc` · `cGDFW`).
/// 높이 56 · 왼쪽 여백 12 · 뒤로 48×48(arrow-left 22 ink). 03 의 앱바와 같은 값이다.
/// 화살표는 [onBack] 에 03 처럼 시스템 뒤로와 **같은 함수**를 받는다(`methodBack`). 사진을 올리는 중에도 숨기지 않는다(깜빡임).
class MethodBackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MethodBackAppBar({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 56,
      backgroundColor: AppColors.canvas,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: AppSpacing.sm + 48,
      leading: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        // leading 자리는 높이 56 을 꽉 채운다 — 가운데에 두어야 누름 칸이 pen 대로 48×48 이다.
        child: Center(
          child: IconButton(
            tooltip: onboardingBackLabel,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: onBack,
            icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}
