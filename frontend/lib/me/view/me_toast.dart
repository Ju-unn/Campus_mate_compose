import 'dart:async';

import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/widgets.dart';

/// "곧 열려요" — 홈 하트 칩 "+" 처럼 갈 화면이 아직 없는 입구. 15-5 "교체" 는 15-7(A15), "수정 ›" 은 15-6(A16)으로 연결됐다.
const comingSoonToast = AppToast(
  leading: Icon(AppIcons.clock3, size: 16, color: AppColors.onInk),
  label: '곧 열려요',
);

/// "저장했어요" — 15-6 에서 저장하고 15-5 로 돌아왔을 때(B4). 아이콘은 조각 6 완료 토스트(`yEDB9`)와 같은 circle-check 16.
const savedToast = AppToast(
  leading: Icon(AppIcons.circleCheck, size: 16, color: AppColors.onInk),
  label: '저장했어요',
);

/// 나 탭 화면(15 · 15-5)이 잠깐 띄우는 안내 하나. 한 번에 하나 — 새 안내는 떠 있던 것을 바로 바꾸고 시간을 새로 잰다.
/// 나타날 때만 [toastEntrance] 로 올라온다(바뀔 때는 제자리에서 글만 바뀐다). 사라질 때는 움직임 없이 사라진다.
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
/// 본문이 유리 내비 뒤로 이어지는 탭 화면(09b · 15)은 본문 MediaQuery padding.bottom 이 알약 자리라 그만큼 올린다
/// (15-5 는 SafeArea 가 이미 그 값을 써 0 이다).
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
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
            child: Center(child: toastEntrance(toast)),
          ),
      ],
    );
  }
}

/// 토스트가 나타날 때 투명 · 아래 8 에서 제자리로 온다 — 대화 탭 SnackBar 토스트(투명 + 아래에서 올라옴)와 느낌을 맞춘다(D4).
/// 대장 지시는 150ms 지만 모션은 토큰만 쓴다(CLAUDE.md §1-2) — `{motion.press}` 120ms. 동작 줄이기면 처음부터 제자리.
/// 나 탭 · 홈 · 코호트 대기 · 하트 상점 · 내 사진이 같이 쓴다.
Widget toastEntrance(Widget toast) =>
    Entrance(rise: AppSpacing.xs, duration: AppMotion.press, curve: AppMotion.pressCurve, child: toast);
