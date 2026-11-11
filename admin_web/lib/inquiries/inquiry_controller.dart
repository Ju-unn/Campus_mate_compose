import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/cursor_page.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/inquiries/inquiry_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/state/paged_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 목록 상태 필터. null = 전체. 신고 목록(기본 "열림")처럼 처음에는 처리할 "새 문의"만 본다.
/// 상세에 갔다 "← 문의 목록" 으로 와도 남게 화면 밖(앱이 켜진 동안)에 둔다.
final inquiryFilterProvider = NotifierProvider<InquiryFilterController, InquiryStatus?>(InquiryFilterController.new);

class InquiryFilterController extends Notifier<InquiryStatus?> {
  @override
  InquiryStatus? build() => InquiryStatus.newInquiry;

  void set(InquiryStatus? status) => state = status;
}

/// 문의 목록 — 화면에 들어올 때마다 새로 받고(처리 뒤 돌아오면 새 상태), 필터가 바뀌면 처음부터, 더 보기는 같은 필터로 이어 받는다.
final inquiryListProvider = NotifierProvider.autoDispose<InquiryListController, PagedState<InquiryItem>>(InquiryListController.new);

class InquiryListController extends PagedController<InquiryItem> {
  late AdminApi _api;
  late InquiryStatus? _status;

  @override
  PagedState<InquiryItem> build() {
    _api = ref.watch(adminApiProvider);
    _status = ref.watch(inquiryFilterProvider);
    return super.build();
  }

  @override
  Future<CursorPage<InquiryItem>> fetch(String? before) => _api.listInquiries(status: _status, before: before);
}

/// 상세 한 건의 상태. [saving] 이 있으면 그 저장을 보내는 중, [failure] 는 마지막 저장 실패(다음 저장을 시작하면 지운다).
class InquiryDetail {
  const InquiryDetail(this.item, {this.saving = false, this.failure});

  final InquiryItem item;
  final bool saving;
  final AdminApiFailure? failure;

  /// 이미 지워진 문의(1년 보관이 지난 뒤 등)
  bool get isGone => failure?.statusCode == 404;
}

/// 상세 화면의 한 건. 목록에서 고른 줄을 처음 값으로 들고, 처리 응답(서버가 돌려준 바뀐 줄)으로 바꾼다.
final inquiryDetailProvider = NotifierProvider.autoDispose.family<InquiryDetailController, InquiryDetail, InquiryItem>(
  InquiryDetailController.new,
);

class InquiryDetailController extends Notifier<InquiryDetail> {
  InquiryDetailController(this.seed);

  final InquiryItem seed;

  @override
  InquiryDetail build() => InquiryDetail(seed);

  /// 상태 바꾸기. 같은 상태면 보내지 않는다. 저장됐으면 true.
  Future<bool> setStatus(InquiryStatus status) {
    if (status == state.item.status) return Future.value(false);
    return _save(status: status);
  }

  /// 메모 저장(빈 글이면 서버가 메모를 지운다). 저장됐으면 true.
  Future<bool> saveMemo(String memo) => _save(memo: memo);

  Future<bool> _save({InquiryStatus? status, String? memo}) async {
    if (state.saving) return false; // 같은 요청이 둘 가지 않게
    state = InquiryDetail(state.item, saving: true);
    final InquiryItem updated;
    try {
      updated = await ref.read(adminApiProvider).updateInquiry(state.item.id, status: status, memo: memo);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted) return false;
      state = InquiryDetail(state.item, failure: failure);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return false;
    }
    if (!ref.mounted) return false;
    state = InquiryDetail(updated);
    return true;
  }
}
