import 'dart:async';

import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱의 최상위 화면(하단 내비 탭 · 시작 화면)을 감싸, 안드로이드 시스템 뒤로가기로 앱이 바로 닫히지 않게 한다.
/// 처음 누르면 "한 번 더 누르면 종료돼요" 를 띄우고, [backExitWindow] 안에 한 번 더 누르면 앱을 닫는다.
///
/// **앱이 닫히려는 순간에만** 가로챈다: 위에 시트 · 다이얼로그 · 다른 화면이 열려 있으면 이 화면의 PopScope 는
/// 불리지 않고, 다른 화면 위에 올라온 탭이면(알림 → 오늘 탭 등) 안내 없이 그 화면으로 돌아간다.
/// iOS · 웹에는 시스템 뒤로가기가 없거나 브라우저 몫이라 [defaultTargetPlatform] 이 안드로이드일 때만 켠다.
class BackExitScope extends ConsumerWidget {
  const BackExitScope({required this.child, this.onHint, super.key});

  final Widget child;

  /// 안내를 띄우는 방법. 비우면 하단 내비 위 SnackBar 토스트 — 시작 화면처럼 자기 토스트 자리가 있으면 그걸 준다.
  final VoidCallback? onHint;

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: !_isAndroid,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final navigator = Navigator.of(context);
        // 이 화면이 맨 아래가 아니면 앱이 닫힐 일이 아니다 — 평소처럼 한 단계 뒤로.
        if (navigator.canPop()) {
          navigator.pop();
          return;
        }
        switch (ref.read(backExitViewModelProvider).onBackPressed()) {
          case BackExitAction.showHint:
            (onHint ?? () => _showHint(context))();
          case BackExitAction.exit:
            unawaited(SystemNavigator.pop());
        }
      },
      child: child,
    );
  }
}

/// 04-2 · 10b 토스트와 같은 자리(하단 내비 위 16, 가로 가운데)와 만드는 방식. 시간은 [backExitWindow] 로 맞춘다.
void _showHint(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        // SnackBar 기본(바깥 아래 10 + 안쪽 위아래 14)을 걷어 내야 내비 위 16 이 된다(poll_toast.dart 와 같다).
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        duration: backExitWindow,
        content: const Center(
          child: AppToast(
            leading: Icon(AppIcons.info, size: 16, color: AppColors.onInk),
            label: backExitMessage,
          ),
        ),
      ),
      // 모션 줄이기를 켜 둔 사람에게는 올라오는 움직임 없이 바로 보여 준다.
      snackBarAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
    );
}
