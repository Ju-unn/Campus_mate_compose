import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';

/// 앱의 SnackBar 는 모두 이 파일의 두 함수로 띄운다 — 움직임을 이 한 곳이 정한다(사용자 2026-11-16, DESIGN §7).
/// `ScaffoldMessenger.showSnackBar` 를 화면에서 직접 부르지 않는다(시험 `motion_entry_points_test.dart` 가 지킨다).

/// 스낵바(띠) — 아래에서 자기 높이만큼 올라오고(easeOut) 같은 길로 내려간다(easeIn).
/// 사용자 「스낵바 아래에서 위로 올라오게 slide in 들어올땐 ease out 나갈때 ease in」.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
  ScaffoldMessengerState messenger,
  SnackBar snackBar,
) =>
    messenger.showSnackBar(_MotionSnackBar(snackBar, slide: true), snackBarAnimationStyle: _style);

/// pen Toast 알약을 SnackBar 자리(하단 내비 위 · 화면 아래)에 띄울 때 — 토스트 규칙대로 자리는 그대로 두고
/// fade 로만 나타났다 사라진다(화면 안 토스트 `ToastPresence` 와 같은 값). 사용자 「토스트는 제자리에서 fade로 나타났다 사라지게」.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showToastSnackBar(
  ScaffoldMessengerState messenger,
  SnackBar snackBar,
) =>
    messenger.showSnackBar(_MotionSnackBar(snackBar, slide: false), snackBarAnimationStyle: _style);

/// 시간은 늘 이 하나다. ScaffoldMessenger 는 컨트롤러 하나를 모든 SnackBar 가 같이 쓰는데, 다른 시간으로 띄우면 그 컨트롤러를
/// 버리고 새로 만들어(Flutter `_didUpdateAnimationStyle`) 사라지던 SnackBar 가 끝나지 못하고 줄이 멈춘다.
/// 그래서 기기 "동작 줄이기" 도 시간을 0 으로 바꾸지 않고 움직임만 빼고 그린다.
const _style = AnimationStyle(duration: AppMotion.appear, reverseDuration: AppMotion.disappear);

/// 받은 SnackBar 를 안쪽에 그대로 그리되 SnackBar 기본 움직임(높이로 드러내기 · 가운데 구간 fade)은 늘 다 나온 상태로 멈추고,
/// 바깥에서 이 파일의 움직임만 준다. 메신저 · Scaffold 가 이 위젯에서 읽는 값(시간 · 행동 · 남기기 · 모양 · 폭)은 그대로 넘긴다.
class _MotionSnackBar extends SnackBar {
  _MotionSnackBar(this.base, {required this.slide, super.key, super.animation})
      : super(
          content: base.content,
          duration: base.duration,
          action: base.action,
          persist: base.persist,
          behavior: base.behavior,
          width: base.width,
        );

  final SnackBar base;

  /// true 면 아래에서 올라오고, false 면 제자리 fade.
  final bool slide;

  /// 메신저가 컨트롤러를 붙일 때 이 종류를 잃지 않게 한다(기본 구현은 그냥 SnackBar 를 만든다).
  @override
  SnackBar withAnimation(Animation<double> newAnimation, {Key? fallbackKey}) =>
      _MotionSnackBar(base, slide: slide, key: key ?? fallbackKey, animation: newAnimation);

  @override
  State<SnackBar> createState() => _MotionSnackBarState();
}

class _MotionSnackBarState extends State<_MotionSnackBar> {
  static final _fromBelow = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero);

  late CurvedAnimation _curve = _curveOf(widget.animation!);
  bool _wasVisible = false;

  static CurvedAnimation _curveOf(Animation<double> parent) =>
      CurvedAnimation(parent: parent, curve: AppMotion.appearCurve, reverseCurve: AppMotion.disappearReverseCurve);

  @override
  void initState() {
    super.initState();
    widget.animation!.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(_MotionSnackBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      oldWidget.animation!.removeStatusListener(_onStatus);
      widget.animation!.addStatusListener(_onStatus);
      _curve.dispose();
      _curve = _curveOf(widget.animation!);
    }
  }

  @override
  void dispose() {
    widget.animation!.removeStatusListener(_onStatus);
    _curve.dispose();
    super.dispose();
  }

  /// 안쪽 SnackBar 는 멈춘 애니메이션을 받아 onVisible 을 부르지 못한다 — 다 나타났을 때 여기서 한 번 부른다.
  void _onStatus(AnimationStatus status) {
    if (status.isCompleted && !_wasVisible) {
      _wasVisible = true;
      widget.base.onVisible?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bar = widget.base.withAnimation(kAlwaysCompleteAnimation);
    if (MediaQuery.disableAnimationsOf(context)) {
      return bar;
    }
    return widget.slide
        ? SlideTransition(position: _curve.drive(_fromBelow), child: bar)
        // 토스트는 liveRegion — 투명한 첫 장면에도 낭독기 트리에 남겨 바로 읽히게 한다.
        : FadeTransition(opacity: _curve, alwaysIncludeSemantics: true, child: bar);
  }
}
