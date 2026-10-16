import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 투어 대상을 받아 두는 곳 — 앱 투어 호스트(`AppTourHost`)가 [TourTargetScope] 로 화면들 위에 내려 준다.
abstract interface class TourTargetRegistry {
  void register(TourTargetId id, BuildContext context);

  void unregister(TourTargetId id, BuildContext context);

  /// 지금 목록 끝 빈자리([TourScrollRoom])를 내야 하는 대상. 없으면 null.
  ValueListenable<TourTargetId?> get scrollRoom;
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

/// 목록 맨 끝에 두는 빈자리. 투어가 이 목록의 [id] 대상을 앱바 바로 아래로 올려 보일 때(단계의 `alignTop`)만 화면 높이만큼
/// 늘어난다 — 목록 끝 대상은 그대로는 더 위로 밀 수 없어서다. 그 밖에는 높이 0 이고, 호스트가 없으면(화면 시험) 늘 0 이다.
class TourScrollRoom extends StatelessWidget {
  const TourScrollRoom({required this.id, super.key});

  final TourTargetId id;

  @override
  Widget build(BuildContext context) {
    final room = context.getInheritedWidgetOfExactType<TourTargetScope>()?.registry.scrollRoom;
    if (room == null) return const SizedBox.shrink();
    return ValueListenableBuilder<TourTargetId?>(
      valueListenable: room,
      builder: (context, current, _) => SizedBox(height: current == id ? MediaQuery.sizeOf(context).height : 0),
    );
  }
}
