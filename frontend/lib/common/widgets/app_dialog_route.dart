import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';

/// 가운데 팝업(확인 창 등)을 띄운다 — showDialog 와 같고(바깥 탭 닫기 · 안전 영역 · 테마), 뒤는 모달 딤 토큰
/// (`AppColors.scrim`, pen 확인 팝업 값표), 움직임은 앱 규칙이다([PopupMotion]: 살짝 커지며 나타나고 닫힐 때 짧게 흐려지며 살짝 줄어든다).
/// 화면에서 showDialog · showGeneralDialog 를 직접 부르지 않는다(시험 `motion_entry_points_test.dart` 가 지킨다).
Future<T?> showAppDialog<T>({required BuildContext context, required WidgetBuilder builder}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    AppDialogRoute<T>(
      context: context,
      barrierColor: AppColors.scrim,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (context) => PopupMotion(child: builder(context)),
    ),
  );
}

/// 앱 팝업 경로 — 시간은 앱 토큰(나타남 220 · 사라짐 180, 기기 "동작 줄이기" 면 0)이고, 화면 전체에 Material 기본 fade 를
/// 걸지 않는다. 움직임은 안쪽에 둔 [PopupMotion] 이 맡는다 — 말풍선 메뉴처럼 막 위에 다시 그린 말풍선은 그대로 두고
/// 메뉴만 커져야 하는 곳이 있다. 딤은 Flutter 기본대로 경로를 따라 fade 로 짙어진다.
class AppDialogRoute<T> extends DialogRoute<T> {
  AppDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierColor,
    super.barrierLabel,
    super.useSafeArea,
  }) : _reduceMotion = MediaQuery.disableAnimationsOf(context),
       super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final bool _reduceMotion;

  @override
  Duration get transitionDuration => _reduceMotion ? Duration.zero : AppMotion.appear;

  @override
  Duration get reverseTransitionDuration => _reduceMotion ? Duration.zero : AppMotion.disappear;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// 팝업이 살짝 커지며(0.96 → 1, easeOut) 나타나고, 닫힐 때 짧게 흐려지며 살짝 줄어든다(easeIn).
/// 사용자 2026-11-16 「팝업은 scale in ease out을 줘서 살짝 커지면서 나오게」. 둘러싼 경로의 진행을 따르고, 경로 밖이거나
/// 기기 "동작 줄이기" 면 그대로 그린다. [alignment] 는 커지는 기준점 — 가운데 팝업은 가운데, 말풍선 메뉴는 말풍선에 붙은 모서리.
class PopupMotion extends StatefulWidget {
  const PopupMotion({required this.child, this.alignment = Alignment.center, super.key});

  final Widget child;
  final Alignment alignment;

  @override
  State<PopupMotion> createState() => _PopupMotionState();
}

class _PopupMotionState extends State<PopupMotion> {
  static final _scale = Tween<double>(begin: AppMotion.popupScaleFrom, end: 1);

  CurvedAnimation? _curve;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route != _curve?.parent) {
      _curve?.dispose();
      _curve = route == null
          ? null
          : CurvedAnimation(parent: route, curve: AppMotion.appearCurve, reverseCurve: AppMotion.disappearReverseCurve);
    }
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    if (curve == null || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: curve,
      // 열리는 첫 장면부터 낭독기가 팝업 글을 읽을 수 있게 한다.
      alwaysIncludeSemantics: true,
      child: ScaleTransition(scale: curve.drive(_scale), alignment: widget.alignment, child: widget.child),
    );
  }
}
