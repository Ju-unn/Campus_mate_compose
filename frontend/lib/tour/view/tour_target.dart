import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:flutter/widgets.dart';

/// 투어 대상을 받아 두는 곳 — 앱 투어 호스트(`AppTourHost`)가 [TourTargetScope] 로 화면들 위에 내려 준다.
abstract interface class TourTargetRegistry {
  void register(TourTargetId id, BuildContext context);

  void unregister(TourTargetId id, BuildContext context);
}

/// 호스트가 라우터 위에 두는 범위. 이 밑의 [TourTarget] 이 자기를 등록한다.
class TourTargetScope extends InheritedWidget {
  const TourTargetScope({required this.registry, required super.child, super.key});

  final TourTargetRegistry registry;

  @override
  bool updateShouldNotify(TourTargetScope oldWidget) => registry != oldWidget.registry;
}

/// 투어가 가리킬 화면 요소에 씌우는 표식. 그리는 것은 [child] 그대로이고 자리 · 크기도 바꾸지 않는다 —
/// 호스트가 이 표식의 그려진 상자(RenderBox)를 재서 구멍을 뚫는다. 호스트가 없으면(화면 시험) 아무 일도 안 한다.
class TourTarget extends StatefulWidget {
  const TourTarget({required this.id, required this.child, super.key});

  final TourTargetId id;
  final Widget child;

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  TourTargetRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = context.getInheritedWidgetOfExactType<TourTargetScope>()?.registry;
    if (registry == _registry) return;
    _registry?.unregister(widget.id, context);
    _registry = registry?..register(widget.id, context);
  }

  @override
  void didUpdateWidget(TourTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id) return;
    _registry?.unregister(oldWidget.id, context);
    _registry?.register(widget.id, context);
  }

  @override
  void dispose() {
    _registry?.unregister(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
