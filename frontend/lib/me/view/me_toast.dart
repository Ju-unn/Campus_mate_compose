import 'dart:async';

import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/widgets.dart';

/// "곧 열려요" — 갈 화면이 아직 없는 입구(15-5 "수정 ›" N4, 15b-3 "하트 충전하기" C5). "교체" 는 15e 로 연결됐다(A15).
const comingSoonToast = AppToast(
  leading: Icon(AppIcons.clock3, size: 16, color: AppColors.onInk),
  label: '곧 열려요',
);

/// 나 탭 화면(15 · 15-5)이 잠깐 띄우는 안내 하나. 한 번에 하나 — 새 안내는 떠 있던 것을 바로 바꾸고 시간을 새로 잰다.
/// 움직임 없이 나타나고 사라진다.
mixin MeToastHost<T extends StatefulWidget> on State<T> {
  /// 떠 있는 시간(사용자 결정 2026-09-27, 약 2초). 15-3 실패 안내도 같다(옛 A8 C7).
  static const Duration duration = Duration(seconds: 2);

  Timer? _timer;
  AppToast? _toast;

  /// 지금 떠 있는 안내. 없으면 null.
  AppToast? get timedToast => _toast;

  void showTimedToast(AppToast toast) {
    if (!mounted) return;
    _timer?.cancel();
    setState(() => _toast = toast);
    _timer = Timer(duration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// [child] 위, 화면 아래 12 · 가로 가운데에 [toast] 를 얹는다. 토스트 공통 규칙(DESIGN §8.5)은 "하단 버튼 위 12" 인데
/// 15 · 15-5 는 하단 버튼이 없어 본문 아래 끝(15 는 내비 바로 위)에서 12 — 04-3 토스트와 같은 자리다(N18).
class MeToastLayer extends StatelessWidget {
  const MeToastLayer({required this.toast, required this.child, super.key});

  final Widget? toast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final toast = this.toast;
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (toast != null)
          Positioned(left: 0, right: 0, bottom: AppSpacing.sm, child: Center(child: toast)),
      ],
    );
  }
}
