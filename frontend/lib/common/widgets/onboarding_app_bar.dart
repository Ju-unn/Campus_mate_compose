import 'package:campus_mate/common/widgets/progress_dots.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// 온보딩 공용 앱바(datingApp.pen `AppBar · Onboarding` · `AppBar · Survey`).
/// 높이 56, 왼쪽 48×48 뒤로가기, 가운데는 진행 표시뿐이다 — 글자 제목은 두지 않는다.
class OnboardingAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OnboardingAppBar({
    required this.current,
    required this.total,
    this.isBar = false,
    this.onBack,
    this.action,
    super.key,
  });

  /// 0부터 센 현재 단계.
  final int current;
  final int total;

  /// 설문(05-01~05-11)은 점 대신 막대를 쓴다.
  final bool isBar;

  /// 화면 안에서 뒤로 갈 곳이 있을 때만 넘긴다(예: 설문 이전 문항).
  /// 서버가 단계를 고정하므로 라우트를 되돌릴 수 없는 화면에서는 빈 자리로 둔다.
  final VoidCallback? onBack;
  final Widget? action;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final canGoBack = onBack != null || Navigator.of(context).canPop();
    return AppBar(
      toolbarHeight: 56,
      backgroundColor: AppColors.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: true,
      titleSpacing: 0,
      leading: canGoBack
          ? IconButton(
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(AppIcons.arrowLeft, color: AppColors.ink),
            )
          : const SizedBox(width: 48, height: 48),
      title: isBar ? _bar() : ProgressDots(current: current, total: total),
      actions: [action ?? const SizedBox(width: 48, height: 48)],
    );
  }

  Widget _bar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: (current + 1) / total,
        minHeight: 5,
        backgroundColor: AppColors.hairlineSoft,
        color: AppColors.primary,
      ),
    );
  }
}
