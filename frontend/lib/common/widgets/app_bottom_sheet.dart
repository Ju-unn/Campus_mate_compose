import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';

/// 앱의 바텀시트는 모두 이것으로 띄운다 — 아래에서 올라오고(slide) 뒷배경은 모달 딤 토큰(`AppColors.scrim`)까지 fade 로
/// 어두워진다(사용자 2026-11-16 「바텀시트는 아래에서 slide in 으로 올리고 뒷배경은 fade 어두워지게」). 둘 다 Flutter 기본
/// 움직임 그대로이고 시간 · 커브만 앱 토큰이다([appSheetAnimationStyle]). 바탕은 투명 — 시트 모양은 각 시트가 그린다.
/// 화면에서 showModalBottomSheet 를 직접 부르지 않는다(시험 `motion_entry_points_test.dart` 가 지킨다).
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: Colors.transparent,
    // Flutter 기본 딤(검정 54%)은 시안보다 어둡다 — 모달 딤 토큰(50%)을 쓴다.
    barrierColor: AppColors.scrim,
    sheetAnimationStyle: appSheetAnimationStyle(context),
  );
}

/// 시트 움직임 값: 올라올 때 standard(220ms · easeOutCubic — DESIGN §7 "시트 열림"), 내려갈 때 180ms easeIn.
/// 기기 "동작 줄이기" 면 움직이지 않는다. 경로를 직접 만드는 곳(`ModalBottomSheetRoute`)도 이것을 준다.
AnimationStyle appSheetAnimationStyle(BuildContext context) => MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.appear,
        reverseDuration: AppMotion.disappear,
        curve: AppMotion.standardCurve,
        reverseCurve: AppMotion.disappearReverseCurve,
      );
