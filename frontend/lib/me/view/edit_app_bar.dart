import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 나 탭 편집 화면 앱바(pen 15c `iq3jl` — 15-7 · 15-6 도 같은 틀, 계획서 D5). 태그 3종 · 06-1 을 편집 모드로 띄울 때도 쓴다.
/// 높이 56, 안쪽 [0,8] · 간격 4, 뒤로 48(arrow-left 22 ink), 제목 20/700 ink x60. 나 탭 전용이라 common 에 두지 않는다.
class EditAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EditAppBar({required this.title, super.key});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 56,
      // 스크롤 아래로 본문이 지나가도 앱바 색이 바뀌지 않는다(pen 에 그런 모양이 없다 — 온보딩 앱바와 같다).
      backgroundColor: AppColors.canvas,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      titleSpacing: AppSpacing.xxs,
      // 편집 화면은 늘 화면 15 · 15c 위에 올라온다 — 되돌아갈 곳이 없을 때(주소로 바로 연 경우)만 뒤로를 숨긴다.
      leading: Navigator.of(context).canPop()
          ? Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              // leading 자리는 높이를 56 으로 꽉 채워 준다 — 가운데에 두어야 누름 칸이 pen 대로 48×48 이다.
              child: Center(
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
                ),
              ),
            )
          : null,
      title: Text(title, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
    );
  }
}
