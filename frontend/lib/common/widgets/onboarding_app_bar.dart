import 'package:campus_mate/common/widgets/progress_dots.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 뒤로 화살표의 읽기 라벨. 앱에 한국어 Material 번역(flutter_localizations)이 없어
/// `MaterialLocalizations.backButtonTooltip` 을 쓰면 "Back" 으로 읽힌다 — flutter 한국어 값과 같은 글자를 둔다.
const String onboardingBackLabel = '뒤로';

/// 온보딩 공용 앱바(datingApp.pen `AppBar · Onboarding` LTFQg · `AppBar · Survey` GCEmW).
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

  /// 설문(05-01~05-11)과 그 뒤 아바타 결과 화면(05-12 계열)은 점 대신 막대를 쓴다.
  final bool isBar;

  /// 화면 안에서 뒤로 갈 곳이 있을 때만 넘긴다(설문 이전 문항 · 온보딩 앞 단계 · 20d → 20).
  /// 없고 위에 쌓인 화면도 아니면(04-1 · 04-4 등) 화살표 없이 빈 48 자리로 둔다 — 진행 점 자리는 그대로다.
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
      // pen 마스터 LTFQg: 안쪽 [0,8] · 뒤로 B8pl1 48×48(arrow-left 22 ink) · 오른쪽 빈 칸 48. 왼쪽 자리는 8 + 48 = 56 이다.
      leadingWidth: _sideWidth,
      leading: canGoBack ? _backButton(context) : const SizedBox(width: _sideWidth, height: 48),
      title: isBar ? _bar() : ProgressDots(current: current, total: total),
      // 점형(LTFQg)은 오른쪽 빈 칸 48 + 안쪽 8 = 왼쪽과 같은 56 — 진행 점이 화면 가운데(360 폭이면 180)에 온다.
      // 막대형(GCEmW)은 오른쪽 빈 칸이 없고 안쪽 24 뿐이다. 20d 건너뛰기(qcQvZ)도 오른쪽 안쪽 8.
      actionsPadding: EdgeInsets.only(right: isBar ? AppSpacing.lg : AppSpacing.xs),
      actions: [action ?? SizedBox(width: isBar ? 0 : 48, height: 48)],
    );
  }

  static const double _sideWidth = AppSpacing.xs + 48;

  Widget _backButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      // leading 자리는 높이를 56 으로 꽉 채워 준다 — 가운데에 두어야 누름 칸이 pen 대로 48×48 이다(EditAppBar 와 같다).
      child: Center(
        child: IconButton(
          tooltip: onboardingBackLabel,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
        ),
      ),
    );
  }

  /// pen IHitX: 뒤로 칸 다음 간격 4 → x60 ~ 336(폭 fill), 높이 5, 바탕 #DDDDDD · 채움 #FF385C · pill.
  Widget _bar() {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xxs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: LinearProgressIndicator(
          value: (current + 1) / total,
          minHeight: 5,
          backgroundColor: AppColors.hairline,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
