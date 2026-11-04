import 'dart:math' as math;

import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

/// [AppLottieView] 가 장면을 되풀이하는 방식.
enum AppLottiePlayback {
  /// 처음 구간(json 의 `intro` 표시)을 한 번 재생한 뒤 반복 구간(`loop` 표시)만 되풀이한다.
  /// `intro` 가 없으면 곧바로 반복 구간, `loop` 가 없으면 [wholeLoop] 와 같다.
  introThenLoop,

  /// 처음부터 끝까지를 통째로 되풀이한다.
  wholeLoop,
}

/// 움직이는 그림(Lottie) 장면 하나를 그리는 앱 **하나뿐인** 자리 — 화면은 이 위젯으로만 Lottie 를 쓴다
/// (`test/common/widgets/app_lottie_view_test.dart` 가 lib 전체를 훑어 지킨다).
///
/// - 기기 "동작 줄이기"(`MediaQuery.disableAnimationsOf`)면 움직이지 않고 [LottieScene.stillFrame] 한 장면에 선다.
///   켜고 끄는 것을 실행 중에도 따른다(DESIGN.md §7).
/// - 파일을 못 읽거나 json 이 깨졌으면 예외 없이 [fallback](없으면 받은 크기의 빈 상자)을 보인다.
/// - [semanticLabel] 이 없으면 장식이라 낭독기에서 뺀다. 그림이 뜻을 가지면(예: 로고) 라벨을 준다.
/// - 색은 그림 속 색 그대로다(앱 토큰으로 바꾸지 않는다).
class AppLottieView extends StatefulWidget {
  const AppLottieView({
    required this.scene,
    this.playback = AppLottiePlayback.introThenLoop,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.semanticLabel,
    this.fallback,
    super.key,
  });

  final LottieScene scene;
  final AppLottiePlayback playback;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// 낭독기가 읽을 설명. null 이면 장식으로 보고 읽지 않는다.
  final String? semanticLabel;

  /// 파일을 못 읽을 때 대신 보일 멈춘 위젯. null 이면 빈 상자.
  final Widget? fallback;

  @override
  State<AppLottieView> createState() => _AppLottieViewState();
}

class _AppLottieViewState extends State<AppLottieView> with SingleTickerProviderStateMixin {
  /// 장면의 진행(0~1)을 쥔 컨트롤러. 길이는 json 을 읽은 뒤 정해진다.
  late final AnimationController _controller = AnimationController(vsync: this);
  LottieComposition? _composition;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    _apply();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLoaded(LottieComposition composition) {
    _composition = composition;
    _controller.duration = composition.duration;
    _apply();
  }

  /// 읽은 장면과 "동작 줄이기" 상태에 맞춰 멈추거나 재생한다.
  void _apply() {
    final composition = _composition;
    if (composition == null) return;
    _controller.stop();
    if (_reducedMotion) {
      _controller.value = _progressOf(composition, widget.scene.stillFrame);
      return;
    }
    _play(composition);
  }

  void _play(LottieComposition composition) {
    final loop = composition.getMarker('loop');
    if (loop == null || widget.playback == AppLottiePlayback.wholeLoop) {
      _controller.value = 0;
      _controller.repeat(period: composition.duration);
      return;
    }
    final intro = composition.getMarker('intro');
    if (intro == null) {
      _repeatLoop(composition, loop);
      return;
    }
    _controller.value = intro.start;
    _controller.animateTo(math.min(intro.end, 1.0), duration: _lengthOf(composition, intro)).then((_) {
      if (mounted) _repeatLoop(composition, loop);
    });
  }

  void _repeatLoop(LottieComposition composition, Marker loop) {
    _controller.value = loop.start;
    // lottie 는 끝 프레임을 `op - 0.01` 로 읽어, 마지막 프레임까지 닿는 표시의 끝이 1 을 살짝 넘는다 — 컨트롤러 범위(0~1)로 자른다.
    _controller.repeat(min: loop.start, max: math.min(loop.end, 1.0), period: _lengthOf(composition, loop));
  }

  Duration _lengthOf(LottieComposition composition, Marker marker) {
    return Duration(microseconds: (composition.duration.inMicroseconds * (marker.end - marker.start)).round());
  }

  double _progressOf(LottieComposition composition, double frame) {
    return (frame - composition.startFrame) / composition.durationFrames;
  }

  @override
  Widget build(BuildContext context) {
    final animation = Lottie.asset(
      widget.scene.path,
      controller: _controller,
      onLoaded: _onLoaded,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) => SizedBox(width: widget.width, height: widget.height, child: widget.fallback),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: animation);
    return Semantics(label: label, image: true, excludeSemantics: true, child: animation);
  }
}
