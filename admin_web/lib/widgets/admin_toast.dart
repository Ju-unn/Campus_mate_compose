import 'dart:async';

import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_motion.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// pen Web/Toast(nmb2y): 높이 44, web-ink 바탕, 모서리 8, 좌우 16, 흰 체크 16 + 간격 8 + 글자 14/600(보드 PNG 측정).
class AdminToast extends StatelessWidget {
  const AdminToast(this.message, {super.key});

  final String message;

  static _ToastHandle? _current;

  /// 화면 아래 가운데(아래 32 — 대장 결정 10-18)에 [duration] 동안 띄운다. 새로 띄우면 앞의 것은 바로 닫는다.
  /// 아래에서 반 칸 올라오며 나타나고(200ms) 같은 길로 더 빨리(150ms) 나간다. 동작 줄이기면 움직이지 않는다.
  static void show(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    _current?.close(immediately: true);
    final handle = _ToastHandle(message, duration);
    // 관문 화면이 바뀌어도(복사 직후 확인 성공) 떠 있게 맨 위 Overlay 에 단다.
    Overlay.of(context, rootOverlay: true).insert(handle.entry);
    _current = handle;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          height: AdminSizes.control,
          padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.md),
          decoration: BoxDecoration(color: AdminColors.ink, borderRadius: BorderRadius.circular(AdminRadius.sm)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.check, size: 16, color: AdminColors.onPrimary),
              const SizedBox(width: AdminSpacing.xs),
              Text(message, style: AdminTypography.smStrong.copyWith(color: AdminColors.onPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 떠 있는 토스트 하나 — Overlay 자리 · 닫는 시계 · 움직임을 묶는다.
class _ToastHandle {
  _ToastHandle(String message, Duration duration) {
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: AdminSpacing.xl,
        child: Center(child: _ToastMotion(key: _motion, child: AdminToast(message))),
      ),
    );
    _timer = Timer(duration, close);
  }

  final GlobalKey<_ToastMotionState> _motion = GlobalKey<_ToastMotionState>();
  late final OverlayEntry entry;
  late final Timer _timer;
  bool _closed = false;

  Future<void> close({bool immediately = false}) async {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    if (!immediately) await _motion.currentState?.exit();
    if (entry.mounted) entry.remove();
    if (identical(AdminToast._current, this)) AdminToast._current = null;
  }
}

class _ToastMotion extends StatefulWidget {
  const _ToastMotion({super.key, required this.child});

  final Widget child;

  @override
  State<_ToastMotion> createState() => _ToastMotionState();
}

class _ToastMotionState extends State<_ToastMotion> with SingleTickerProviderStateMixin {
  // 곡선은 시간에 건다(animateTo · animateBack) — 들어올 때도 나갈 때도 빠르게 시작해 천천히 멈춘다(ease-out).
  late final AnimationController _controller = AnimationController(vsync: this);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(_controller);
  bool _reduced = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AdminMotion.reduced(context);
    if (_started) return;
    _started = true;
    _controller.animateTo(1, duration: _reduced ? Duration.zero : AdminMotion.enter, curve: AdminMotion.curve);
  }

  /// 같은 길(아래로 반 칸 · 투명)로 더 빨리 나간다. 그 사이 화면이 사라지면 그냥 끝낸다.
  Future<void> exit() async {
    try {
      await _controller
          .animateBack(0, duration: _reduced ? Duration.zero : AdminMotion.exit, curve: AdminMotion.curve)
          .orCancel;
    } on TickerCanceled {
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      // 자기 높이의 반(22) 아래에서 — 크기에 상대적인 값이라 글자 크기가 바뀌어도 같은 느낌이다.
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
