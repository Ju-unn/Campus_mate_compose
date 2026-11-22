import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/list_page.dart';
import 'package:campus_mate_admin/state/paged_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 흉내: [total] 건을 [AdminApi.pageSize] 씩 나눠 준다. 범위 밖 쪽은 빈 줄 + total(서버 약속 그대로).
class _ShrinkingList extends PagedController<int> {
  int total = AdminApi.pageSize + 1;
  final List<int> asked = [];

  @override
  Future<ListPage<int>> fetch(int page) async {
    asked.add(page);
    final start = (page - 1) * AdminApi.pageSize;
    final end = (start + AdminApi.pageSize).clamp(0, total);
    return ListPage(items: [for (var i = start; i < end; i++) i], total: total);
  }
}

final _listProvider = NotifierProvider<_ShrinkingList, PagedState<int>>(_ShrinkingList.new);

void main() {
  test('보던 쪽이 그사이 사라졌으면(건수가 줄었다) 마지막 쪽을 한 번만 다시 받는다', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(_listProvider, (_, _) {});
    final controller = container.read(_listProvider.notifier);
    await pumpEventQueue();

    controller.total = AdminApi.pageSize; // 다른 관리자가 한 건을 처리해 2쪽이 없어졌다
    controller.goTo(2);
    await pumpEventQueue();

    final state = container.read(_listProvider);
    expect((state.page, state.items.length, state.loading), (1, AdminApi.pageSize, false));
    expect(controller.asked, [1, 2, 1]);
  });
}
