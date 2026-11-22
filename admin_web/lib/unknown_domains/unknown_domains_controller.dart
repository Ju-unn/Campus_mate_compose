import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/list_page.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/state/paged_controller.dart';
import 'package:campus_mate_admin/unknown_domains/unknown_domain_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A6 표. 화면에 들어올 때마다 1쪽부터 새로 받는다. 읽기 전용 — 서버가 주는 많은 순을 번호 쪽으로.
final unknownDomainsProvider = NotifierProvider.autoDispose<UnknownDomainsController, PagedState<UnknownDomain>>(UnknownDomainsController.new);

class UnknownDomainsController extends PagedController<UnknownDomain> {
  late AdminApi _api;

  @override
  PagedState<UnknownDomain> build() {
    _api = ref.watch(adminApiProvider);
    return super.build();
  }

  @override
  Future<ListPage<UnknownDomain>> fetch(int page) => _api.unknownDomains(page: page);
}
