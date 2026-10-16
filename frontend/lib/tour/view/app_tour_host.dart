import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/coach_bubble.dart';
import 'package:campus_mate/tour/view/coach_line.dart';
import 'package:campus_mate/tour/view/coach_overlay.dart';
import 'package:campus_mate/tour/view/tour_target.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 구멍이 앞 대상에서 다음 대상으로 옮겨 가는 시간(지시값 280ms). 모션 토큰(`app_motion.dart`)에 없는 값이고
/// 그 파일은 공유 파일이라 여기 둔다 — 커브는 토큰 `standardCurve`(ease-out).
const Duration _travelDuration = Duration(milliseconds: 280);

/// 말풍선 폭(pen `gfoSM` 312). 좁은 화면에서는 좌우 16 을 남기고 줄인다.
const double _bubbleWidth = 312;

/// 대상을 찾는 프레임 수 상한. 넘으면 그 단계를 건너뛴다(앱이 멈추거나 빈 덮개가 남지 않게).
const int _seekFrames = 60;

/// 앞 후보가 이만큼 프레임이 지나도 안 보이면 뒤 후보(대신 자리)를 쓴다 — 화면이 그려질 틈을 준다.
const int _fallbackAfterFrames = 5;

/// 말풍선 자리가 모자랄 때 선을 줄여도 남기는 길이(점 10 + 선 14). pen 에 없는 값 — 작은 화면 · 큰 글자에서만 닿는다.
const double _minLine = AppSpacing.lg;

/// [TourStep.alignTop] 단계에서 구멍 아래를 잘라도 남기는 높이. pen 에 없는 값 — 작은 화면 · 큰 글자에서만 닿는다.
const double _minHole = AppSpacing.xxl;

/// 앱 투어 호스트. 앱 맨 위(`MaterialApp.builder`, 라우터 바깥)에 한 번 놓여 화면이 바뀌어도 덮개가 남는다.
/// 단계([appTourSteps])마다 그 화면으로 옮기고, [TourTarget] 으로 등록된 요소의 그려진 자리를 재서 구멍을 뚫는다.
/// 자리는 매 프레임 끝에 다시 재 회전 · 키보드 · 늦게 그려짐에도 따라간다(프레임을 새로 부르지는 않는다).
///
/// 투어 중에는 밑 화면을 누를 수도 스크린리더로 읽을 수도 없다. 시스템 뒤로가기는 건너뛰기다.
class AppTourHost extends ConsumerStatefulWidget {
  const AppTourHost({required this.router, required this.child, super.key});

  /// 화면을 옮길 라우터. 호스트는 라우터 위에 있어 `GoRouter.of` 로 찾지 못한다.
  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<AppTourHost> createState() => _AppTourHostState();
}

class _AppTourHostState extends ConsumerState<AppTourHost>
    with TickerProviderStateMixin, WidgetsBindingObserver
    implements TourTargetRegistry {
  final Map<TourTargetId, BuildContext> _targets = {};

  /// 목록 끝 빈자리([TourScrollRoom])를 낼 대상 — [TourStep.alignTop] 단계에서만 찬다.
  final ValueNotifier<TourTargetId?> _scrollRoom = ValueNotifier(null);

  /// 빈자리를 붙인 목록 — 투어가 끝날 때 빈자리를 거두기 전에 목록 끝으로 되돌린다.
  ScrollPosition? _roomList;

  /// 말풍선의 잘리지 않은 높이. 매 프레임 끝에 재 말풍선 자리 · 구멍 자르기에 쓴다(처음엔 모른다).
  final GlobalKey _bubbleKey = GlobalKey();
  double? _bubbleHeight;

  /// 덮개 첫 등장 · 끝날 때 사라짐.
  late final AnimationController _appear = AnimationController(vsync: this, duration: AppMotion.standard)
    ..addStatusListener(_onAppearStatus);
  late final Animation<double> _appearCurve = CurvedAnimation(parent: _appear, curve: AppMotion.standardCurve);

  /// 구멍 이동 · 크기 변화.
  late final AnimationController _travel = AnimationController(vsync: this, duration: _travelDuration, value: 1);
  late final Animation<double> _travelCurve = CurvedAnimation(parent: _travel, curve: AppMotion.standardCurve);

  late final ProviderSubscription<AppTourUiState> _tour;

  /// 찾기를 시작할 때마다 오른다 — 앞 찾기가 늦게 끝나도 지금 단계를 덮어쓰지 않는다.
  int _seek = 0;

  /// 말풍선에 보이는 단계와 그 대상(찾은 뒤). 찾는 중에는 null — 말풍선을 숨긴다. 대상이 null 이면 가운데 카드다.
  TourStep? _step;
  BuildContext? _pointed;

  Rect? _from;
  double _fromRadius = 0;
  Rect? _to;
  double _toRadius = 0;
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    // 라우터의 뒤로가기 처리보다 먼저 등록된다(호스트가 라우터의 조상이라 먼저 만들어진다) — 투어 중 뒤로가기를 먼저 받는다.
    WidgetsBinding.instance.addObserver(this);
    _tour = ref.listenManual(appTourViewModelProvider, _onTour);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tour.close();
    _appear.dispose();
    _travel.dispose();
    _scrollRoom.dispose();
    super.dispose();
  }

  @override
  void register(TourTargetId id, BuildContext context) => _targets[id] = context;

  @override
  void unregister(TourTargetId id, BuildContext context) {
    if (identical(_targets[id], context)) _targets.remove(id);
  }

  @override
  ValueListenable<TourTargetId?> get scrollRoom => _scrollRoom;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  AppTourViewModel get _viewModel => ref.read(appTourViewModelProvider.notifier);

  bool get _active => ref.read(appTourViewModelProvider).active;

  void _onTour(AppTourUiState? previous, AppTourUiState next) {
    if (!next.active) {
      _close();
      return;
    }
    final starting = previous == null || !previous.active || previous.run != next.run;
    if (!starting && previous.index == next.index) return;
    if (starting) {
      _from = _to = null;
      _reduced ? _appear.value = 1 : _appear.forward(from: 0);
      _watch();
    }
    unawaited(_seekStep(next));
  }

  void _close() {
    _seek++;
    _releaseRoom();
    setState(() {
      _step = null;
      _pointed = null;
    });
    _reduced ? _appear.value = 0 : _appear.reverse();
  }

  /// 6단계 빈자리를 거둔다. 목록이 빈자리 안까지 내려가 있으면 먼저 목록 끝으로 부드럽게 올린 뒤 거둔다 —
  /// 바로 거두면 목록이 끝으로 한 프레임에 튄다(건너뛰기 · 시스템 뒤로가기). 동작 줄이기면 바로 거둔다.
  void _releaseRoom() {
    final list = _roomList;
    _roomList = null;
    final room = _scrollRoom.value;
    // 목록 화면이 이미 닫혔으면(다른 길로 벗어남 · 시작하기 뒤) 밀 목록이 없다.
    if (_reduced || room == null || list == null || !list.context.storageContext.mounted || !list.hasContentDimensions) {
      _scrollRoom.value = null;
      return;
    }
    // 빈자리 높이 = 화면 높이(TourScrollRoom).
    final end = math.max(list.minScrollExtent, list.maxScrollExtent - MediaQuery.sizeOf(context).height);
    if (list.pixels <= end) {
      _scrollRoom.value = null;
      return;
    }
    unawaited(list.animateTo(end, duration: _travelDuration, curve: AppMotion.standardCurve).whenComplete(() {
      // 그사이 투어를 다시 시작했으면 그쪽이 빈자리를 맡는다.
      if (mounted && !_active && _scrollRoom.value == room) _scrollRoom.value = null;
    }));
  }

  void _onAppearStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() => _from = _to = null);
  }

  /// 단계 화면으로 옮기고 대상을 프레임마다 찾는다. 목록 끝 대상은 목록을 **한 번** 끝으로 밀어 찾는다 —
  /// 목록이 아직 길어지는 중이어도 매 프레임 따라 밀지 않는다(끝내 없으면 그 단계를 건너뛴다).
  Future<void> _seekStep(AppTourUiState tour) async {
    final token = ++_seek;
    final step = appTourSteps[tour.index];
    _scrollRoom.value = null;
    _roomList = null;
    setState(() {
      _step = null;
      _pointed = null;
    });
    _navigate(step);
    var pushed = false;
    for (var frame = 0; step.targets.isNotEmpty && frame < _seekFrames; frame++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || token != _seek) return;
      final found = _find(step, frame);
      if (found != null) {
        _arrive(step, found);
        return;
      }
      if (!pushed) pushed = _scrollTowards(step);
    }
    if (!mounted || token != _seek) return;
    if (step.targets.isEmpty) {
      _arrive(step, null);
      return;
    }
    _missing(tour);
  }

  /// 탭은 하단 내비와 같이 `go`, 위에 올리는 화면은 `push` — 지금 그 화면이면 그대로 둔다.
  void _navigate(TourStep step) {
    if (widget.router.state.matchedLocation == step.location) return;
    if (step.push) {
      unawaited(widget.router.push<void>(step.location));
      return;
    }
    widget.router.go(step.location);
  }

  /// 지금 그려져 있는 첫 후보. 대신 자리(뒤 후보)는 [_fallbackAfterFrames] 가 지난 뒤에만 본다.
  TourTargetId? _find(TourStep step, int frame) {
    for (final (index, id) in step.targets.indexed) {
      if (index > 0 && frame < _fallbackAfterFrames) return null;
      final target = _targets[id];
      if (target != null && _boxRect(target) != null) return id;
    }
    return null;
  }

  /// 손잡이가 든 목록을 끝으로 민다. 밀었으면(또는 이미 끝이면) true — 손잡이 목록이 아직 안 그려졌으면 false 라 다음 프레임에 다시 본다.
  bool _scrollTowards(TourStep step) {
    final anchor = _targets[step.scrollAnchor];
    if (anchor == null || !anchor.mounted) return false;
    final position = Scrollable.maybeOf(anchor)?.position;
    if (position == null || !position.hasContentDimensions) return false;
    if (position.pixels < position.maxScrollExtent) position.jumpTo(position.maxScrollExtent);
    return true;
  }

  /// 그려진 상자를 호스트 좌표로(변환 · 화면 전환 중 확대까지 반영). 아직 안 그려졌으면 null.
  Rect? _boxRect(BuildContext target) {
    if (!target.mounted) return null;
    final box = target.findRenderObject();
    final host = context.findRenderObject();
    if (box is! RenderBox || host is! RenderBox || !box.attached || !box.hasSize || !host.hasSize) return null;
    return MatrixUtils.transformRect(box.getTransformTo(host), Offset.zero & box.size);
  }

  /// 구멍 — 대상 상자를 [TourStep.holePadding] 만큼 띄우고 위아래를 보이는 영역([_visibleArea]) 안으로 줄인다(모든 단계가 같다).
  /// [TourStep.alignTop] 단계는 아래 말풍선 · 선이 보이는 영역 안에 다 들어오게 구멍 아래쪽을 더 자른다(최소 [_minHole]).
  Rect? _rectOf(BuildContext target, TourStep step) {
    final box = _boxRect(target);
    if (box == null) return null;
    final raw = step.holePadding.inflateRect(box);
    final area = _visibleArea(target);
    final top = _within(raw.top, area.top, area.bottom);
    var bottom = _within(raw.bottom, area.top, area.bottom);
    final bubble = _bubbleHeight;
    if (step.alignTop != null && bubble != null) {
      final limit = area.bottom - AppSpacing.md - step.lineLength - bubble;
      bottom = math.max(math.min(bottom, top + _minHole), math.min(bottom, limit));
    }
    return Rect.fromLTRB(raw.left, top, raw.right, bottom);
  }

  /// 대상이 보일 수 있는 위아래 범위(호스트 좌표): 안전 영역 안이고, 대상을 품은 세로 목록마다 그 목록 칸 안 —
  /// 앱바 · 배너 · 하단 고정 바(하트 구매 바)는 목록 칸 밖이라 빠진다. 가로는 줄이지 않는다(pen 가로 띄움 그대로).
  Rect _visibleArea(BuildContext target) {
    var area = MediaQuery.paddingOf(context).deflateRect(Offset.zero & (context.size ?? Size.zero));
    for (var list = Scrollable.maybeOf(target, axis: Axis.vertical);
        list != null;
        list = Scrollable.maybeOf(list.context, axis: Axis.vertical)) {
      final view = _boxRect(list.context);
      if (view == null) continue;
      area = Rect.fromLTRB(area.left, math.max(area.top, view.top), area.right, math.min(area.bottom, view.bottom));
    }
    return area;
  }

  /// [value] 를 [low]~[high] 안으로. 범위가 뒤집혀도(화면 전환 중 목록이 화면 밖) 던지지 않는다.
  static double _within(double value, double low, double high) => math.min(math.max(value, low), high);

  /// 찾았다 — 구멍을 지금 자리(움직이는 중이면 그 중간)에서 새 대상으로 옮기고 말풍선을 띄운다. 대상이 화면 밖이면 보이게 민다.
  void _arrive(TourStep step, TourTargetId? id) {
    final target = _targets[id];
    final to = target == null ? null : _rectOf(target, step);
    setState(() {
      final current = _currentHole();
      _from = current ?? to;
      _fromRadius = current == null ? step.holeRadius : _currentRadius();
      // 가운데 카드(대상 없음)면 구멍을 그 자리에서 닫는다.
      _to = to ?? (current == null ? null : Rect.fromCenter(center: current.center, width: 0, height: 0));
      _toRadius = step.holeRadius;
      _step = step;
      _pointed = target;
    });
    _reduced ? _travel.value = 1 : _travel.forward(from: 0);
    if (target == null) return;
    if (step.alignTop case final gap?) {
      unawaited(_raise(id!, target, step, gap));
      return;
    }
    unawaited(Scrollable.ensureVisible(
      target,
      alignment: 0.5,
      duration: _reduced ? Duration.zero : _travelDuration,
      curve: AppMotion.standardCurve,
    ));
  }

  /// [TourStep.alignTop] — 목록 끝 빈자리를 내고(다음 프레임에 목록이 길어진다) 구멍 위쪽이 보이는 영역 맨 위에서 [gap] 아래에 오게 민다.
  /// 목록이 그만큼 못 가면 갈 수 있는 데까지만.
  Future<void> _raise(TourTargetId id, BuildContext target, TourStep step, double gap) async {
    final token = _seek;
    _scrollRoom.value = id;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || token != _seek) return;
    if (!target.mounted) return;
    final list = Scrollable.maybeOf(target, axis: Axis.vertical);
    final box = _boxRect(target);
    if (list == null || box == null) return;
    final position = list.position;
    _roomList = position;
    final offset = position.pixels + step.holePadding.inflateRect(box).top - (_visibleArea(target).top + gap);
    final to = offset.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (_reduced) return position.jumpTo(to);
    await position.animateTo(to, duration: _travelDuration, curve: AppMotion.standardCurve);
  }

  void _missing(AppTourUiState tour) {
    if (tour.index >= appTourSteps.length - 1) {
      _finish();
      return;
    }
    _viewModel.skipMissing();
  }

  void _next() {
    if (ref.read(appTourViewModelProvider).index >= appTourSteps.length - 1) {
      _finish();
      return;
    }
    _viewModel.next();
  }

  /// 마지막 "시작하기" — 끝내고 홈으로 돌아온다.
  void _finish() {
    _viewModel.end();
    widget.router.go(AppRoutes.home);
  }

  /// 건너뛰기 · 시스템 뒤로가기 — 그 자리에서 끝낸다.
  void _skip() => _viewModel.end();

  @override
  Future<bool> didPopRoute() async {
    if (!mounted || !_active) return false;
    _skip();
    return true;
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => mounted && _active;

  @override
  void handleCommitBackGesture() {
    if (mounted && _active) _skip();
  }

  /// 매 프레임 끝에 대상 자리를 다시 잰다. 프레임을 새로 부르지 않아 화면이 멈춰 있으면 쉬고(pumpAndSettle 이 끝난다),
  /// 자리가 바뀌었을 때만 다시 그린다. 대상이 사라졌으면(알림을 눌러 다른 화면으로 감 등) 빈 덮개를 남기지 않고 끝낸다.
  void _watch() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onFrame(Duration _) {
    if (!mounted || !_active) {
      _watching = false;
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    final step = _step;
    final target = _pointed;
    if (step == null) return;
    if (target == null) {
      // 대상 없는 단계(5단계 가운데 카드)는 재 볼 것이 없다 — 알림 · 로그아웃 · 딥링크로 그 단계 화면을 벗어나면 끝낸다.
      if (widget.router.state.matchedLocation != step.location) _skip();
      return;
    }
    // 말풍선 높이를 먼저 잰다 — 6단계 구멍 자르기와 말풍선 자리가 쓴다(말풍선 높이는 자리와 상관없어 되먹임이 없다).
    final measured = _bubbleKey.currentContext?.size?.height;
    final resized = measured != null && measured != _bubbleHeight;
    if (resized) _bubbleHeight = measured;
    final rect = _rectOf(target, step);
    if (rect == null) {
      _skip();
      return;
    }
    final to = _to;
    if (!resized && to != null && _near(to, rect)) return;
    setState(() => _to = rect);
  }

  static bool _near(Rect a, Rect b) =>
      (a.left - b.left).abs() < 0.5 &&
      (a.top - b.top).abs() < 0.5 &&
      (a.right - b.right).abs() < 0.5 &&
      (a.bottom - b.bottom).abs() < 0.5;

  Rect? _currentHole() {
    final to = _to;
    if (to == null) return null;
    return Rect.lerp(_from ?? to, to, _travelCurve.value);
  }

  double _currentRadius() => lerpDouble(_fromRadius, _toRadius, _travelCurve.value)!;

  @override
  Widget build(BuildContext context) {
    final tour = ref.watch(appTourViewModelProvider);
    return TourTargetScope(
      registry: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 감싸개는 늘 같은 자리에 두고 값만 바꾼다 — 투어를 켜고 끌 때 앱 화면이 새로 만들어지지 않는다.
          // 덮개 그림(CoachOverlay)도 눌림을 받아 밑으로 안 보낸다 — 이 AbsorbPointer 는 그 위에 한 겹 더 둔 막음이다.
          AbsorbPointer(
            absorbing: tour.active,
            child: ExcludeSemantics(excluding: tour.active, child: widget.child),
          ),
          if (tour.active || !_appear.isDismissed)
            IgnorePointer(
              ignoring: !tour.active,
              child: FadeTransition(
                key: const ValueKey('app-tour-overlay'),
                opacity: _appearCurve,
                child: LayoutBuilder(builder: (context, constraints) => _layer(context, constraints.biggest, tour)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _layer(BuildContext context, Size size, AppTourUiState tour) {
    final step = _step;
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _travel,
            builder: (context, _) {
              final hole = _currentHole();
              return CoachOverlay(hole: hole == null || hole.isEmpty ? null : hole, radius: _currentRadius());
            },
          ),
        ),
        if (step != null) ..._bubble(context, size, tour, step),
      ],
    );
  }

  /// 말풍선은 구멍 아래(안 들어가면 위)에 선 길이만큼 떨어져 놓인다(가로는 가운데). 대상이 없으면 화면 가운데.
  /// 자리가 모자라면 선을 줄이고, 그래도 모자라면 화면 안으로 당겨 구멍에 겹친다 — 화면보다 크면(글자 확대 · 가로 화면) 안이 스크롤된다.
  List<Widget> _bubble(BuildContext context, Size size, AppTourUiState tour, TourStep step) {
    final padding = MediaQuery.paddingOf(context);
    final width = math.min(_bubbleWidth, size.width - AppSpacing.md * 2);
    final left = (size.width - width) / 2;
    final key = ValueKey((tour.run, tour.index));
    final bubble = Entrance(
      key: key,
      rise: 8,
      child: CoachBubble(
        key: _bubbleKey,
        number: tour.index - tour.skipped + 1,
        total: appTourSteps.length - tour.skipped,
        title: step.title,
        body: step.body,
        isLast: tour.index == appTourSteps.length - 1,
        detail: step.detail?.call(context),
        onNext: _next,
        onSkip: _skip,
      ),
    );
    final hole = _pointed == null ? null : _to;
    if (hole == null) {
      return [
        Positioned(
          left: left,
          width: width,
          top: padding.top + AppSpacing.md,
          bottom: padding.bottom + AppSpacing.md,
          child: Center(child: SingleChildScrollView(child: bubble)),
        ),
      ];
    }
    final top = padding.top + AppSpacing.md;
    final bottom = size.height - padding.bottom - AppSpacing.md;
    final height = math.min(_bubbleHeight ?? 0, math.max(0.0, bottom - top));
    final below = _bubbleBelow(hole, top, bottom, height);
    final space = below ? bottom - hole.bottom : hole.top - top;
    // 자리가 모자라면 선부터 줄인다(최소 _minLine). 그래도 모자라면 말풍선을 화면 안으로 당겨 구멍에 겹치고 선은 감춘다.
    final line = (space - height).clamp(math.min(_minLine, step.lineLength), step.lineLength).toDouble();
    final overlap = space < height + _minLine;
    // 말풍선의 구멍 쪽 끝 — 아래면 위 끝, 위면 아래 끝.
    final edge = switch ((below, overlap)) {
      (true, false) => hole.bottom + line,
      (true, true) => math.max(top, bottom - height),
      (false, false) => hole.top - line,
      (false, true) => math.min(bottom, top + height),
    };
    final card = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.max(0, below ? bottom - edge : edge - top)),
      child: SingleChildScrollView(child: bubble),
    );
    // 선은 대상 가운데 아래(위)로, 말풍선 모서리 둥근 곳은 피한다.
    final lineX = hole.center.dx.clamp(left + AppSpacing.lg, left + width - AppSpacing.lg);
    return [
      if (!overlap)
        Positioned(
          left: lineX - CoachLine.dotDiameter / 2,
          top: below ? hole.bottom : hole.top - line,
          child: TweenAnimationBuilder<double>(
            key: key,
            tween: Tween(begin: _reduced ? 1 : 0, end: 1),
            duration: AppMotion.standard,
            curve: AppMotion.standardCurve,
            builder: (context, progress, _) => CoachLine(length: line, dotAtTop: below, progress: progress),
          ),
        ),
      if (below)
        Positioned(left: left, width: width, top: edge, child: card)
      else
        Positioned(left: left, width: width, bottom: size.height - edge, child: card),
    ];
  }

  /// 구멍 아래가 먼저(pen), 아래에 안 들어가면 위, 둘 다 안 들어가면 넓은 쪽. [height] 는 말풍선 높이(모르면 0).
  static bool _bubbleBelow(Rect hole, double top, double bottom, double height) {
    final below = bottom - hole.bottom;
    final above = hole.top - top;
    final need = height + _minLine;
    return below >= need || (above < need && below >= above);
  }
}
