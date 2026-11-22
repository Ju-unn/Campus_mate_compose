import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/inquiries/inquiry_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/inquiry_fakes.dart';

/// 문의 관리 API — 서버 계약은 backend/app/admin/inquiry_review.py · tests/inquiries/test_admin_inquiries.py
void main() {
  FakeInquiryServer server0() => FakeInquiryServer(rows: [
    inquiryRow(inquiryA, createdAt: '2026-11-10T01:00:00+00:00'),
    inquiryRow(inquiryB, createdAt: '2026-11-10T02:00:00+00:00', status: 'answered'),
    inquiryRow(inquiryC, createdAt: '2026-11-10T03:00:00+00:00'),
  ]);

  test('목록: 상태가 있으면 status 로 보낸다, 없으면 쪽만 붙인다', () async {
    final server = server0();

    await server.api().listInquiries();
    await server.api().listInquiries(status: InquiryStatus.answered);

    expect([for (final r in server.lists) r.url.queryParameters], [
      {'page': '1', 'size': '20'},
      {'status': 'answered', 'page': '1', 'size': '20'},
    ]);
  });

  test('번호 쪽: page 로 그 쪽을 받고 total 은 같은 필터의 전체 수', () async {
    final server = server0();

    final first = await server.api().listInquiries();
    final second = await server.api().listInquiries(page: 2);

    expect(first.items.map((i) => i.id), [inquiryC, inquiryB, inquiryA]);
    expect(first.total, 3);
    expect(server.lists.last.url.queryParameters, {'page': '2', 'size': '20'});
    expect(second.items, isEmpty);
    expect(second.total, 3);
  });

  test('처리: 바꾼 칸만 PATCH 로 보내고, 응답의 한 줄을 돌려준다', () async {
    final server = server0();

    final updated = await server.api().updateInquiry(inquiryA, status: InquiryStatus.inProgress);
    await server.api().updateInquiry(inquiryA, memo: '  전화 예정 ');

    expect(updated.status, InquiryStatus.inProgress);
    expect([for (final r in server.patches) jsonDecode(r.body)], [
      {'status': 'in_progress'},
      {'admin_memo': '전화 예정'},
    ]);
    expect(server.patches.first.url.path, '/admin/inquiries/$inquiryA');
  });

  test('처리: 꼴이 틀린 번호는 보내지 않고 404 로 실패, 서버 실패는 AdminApiFailure', () async {
    final server = server0();

    await expectLater(server.api().updateInquiry('../me', status: InquiryStatus.answered), throwsA(isA<AdminApiFailure>().having((f) => f.statusCode, 'status', 404)));
    expect(server.patches, isEmpty);
    server.patchFailure = 500;
    await expectLater(server.api().updateInquiry(inquiryA, memo: 'x'), throwsA(isA<AdminApiFailure>().having((f) => f.statusCode, 'status', 500)));
  });
}
