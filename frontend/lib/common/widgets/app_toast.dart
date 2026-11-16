import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 하단 버튼 위에 잠깐 뜨는 알림 띠(datingApp.pen `Toast` 마스터 — 04-3 `wQBW0` · 04-2 `I8UOWm`).
///
/// 앞에 오는 16 짜리 그림만 화면마다 다르다(04-3 은 도는 표시, 04-2 는 경고 아이콘).
class AppToast extends StatelessWidget {
  const AppToast({required this.label, this.leading, super.key});

  /// 16×16 자리에 들어가는 그림. 없으면 글자만 — 15d-3 투표 보상(재화 하트는 Lucide 로 그리지 않는다).
  final Widget? leading;
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
            if (leading != null) ...[
              SizedBox(width: 16, height: 16, child: leading),
              const SizedBox(width: AppSpacing.xs),
            ],
            // 줄높이 20/14 는 pen 렌더 기준(마스터 `I8UOWm` 글자 20, 두 줄 `yEDB9` 40).
            Flexible(child: Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.onInk, height: 20 / 14))),
          ],
        ),
      ),
    );
  }
}

/// 화면 안 토스트가 뜨고 지는 자리 — [child] 가 생기면 제자리에서 fade 로 나타나고(easeOut 220ms), null 이 되면 제자리에서
/// fade 로 사라진다(easeIn 180ms). 사용자 2026-11-16 「토스트는 제자리에서 fade로 나타났다 사라지게」.
/// 사라지는 동안은 자리를 그대로 차지하고 다 사라진 뒤 비운다. 떠 있는 토스트의 글만 바뀌면(같은 종류 위젯) 다시 나타나지 않고
/// 제자리에서 바뀐다. 기기 "동작 줄이기" 면 바로 나타나고 바로 사라진다.
/// [gapBelow] 를 주면 토스트 아래 그만큼 띄운 간격도 토스트와 같이 생기고 없어진다(버튼 위 12 등). 토스트는 가로 가운데에 둔다.
/// SnackBar 자리에 띄우는 토스트는 `showToastSnackBar`(app_snack_bar.dart)가 같은 값으로 움직인다.
class ToastPresence extends StatelessWidget {
  const ToastPresence({required this.child, this.gapBelow = 0, super.key});

  final Widget? child;
  final double gapBelow;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final toast = child;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : AppMotion.appear,
      reverseDuration: reduceMotion ? Duration.zero : AppMotion.disappear,
      switchInCurve: AppMotion.appearCurve,
      switchOutCurve: AppMotion.disappearReverseCurve,
      // 투명할 때도 낭독기 트리에 남긴다 — 토스트는 liveRegion 이라 나타나는 첫 장면에 읽혀야 한다.
      // 동작 줄이기면 흐려짐 자체를 두지 않는다.
      transitionBuilder: reduceMotion
          ? (child, _) => child
          : (child, animation) => FadeTransition(opacity: animation, alwaysIncludeSemantics: true, child: child),
      layoutBuilder: _layout,
      child: toast == null || gapBelow == 0
          ? toast
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [Center(child: toast), SizedBox(height: gapBelow)],
            ),
    );
  }

  /// 기본 배치와 같되, 아무것도 없을 때는 크기 0 — 빈 Stack 은 받은 제약의 가장 큰 크기를 차지한다.
  static Widget _layout(Widget? current, List<Widget> previous) => current == null && previous.isEmpty
      ? const SizedBox.shrink()
      : Stack(alignment: Alignment.center, children: [...previous, ?current]);
}
