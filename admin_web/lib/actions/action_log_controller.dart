import 'package:campus_mate_admin/actions/action_item.dart';
import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/cursor_page.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/state/paged_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 지금 걸린 대상 id(UUID 모양으로 검사를 마친 것). null = 전체. 화면에 들어올 때마다 전체로 돌아온다.
final actionTargetProvider = NotifierProvider.autoDispose<ActionTargetController, String?>(ActionTargetController.new);

class ActionTargetController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? target) => state = target;
}

/// A7 작업 기록 목록 — 대상 id 가 바뀌면 처음부터 다시, 더 보기는 같은 id 로 이어 받는다.
final actionLogProvider = NotifierProvider.autoDispose<ActionLogController, PagedState<ActionRow>>(ActionLogController.new);

class ActionLogController extends PagedController<ActionRow> {
  late AdminApi _api;
  late String? _target;

  @override
  PagedState<ActionRow> build() {
    _api = ref.watch(adminApiProvider);
    _target = ref.watch(actionTargetProvider);
    return super.build();
  }

  @override
  Future<CursorPage<ActionRow>> fetch(String? before) => _api.listActions(target: _target, before: before);
}
