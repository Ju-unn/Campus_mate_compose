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

  test('목록: 상태가 있으면 status 로 보낸다, 없으면 아무것도 붙이지 않는다', () async {
    final server = server0();

    await server.api().listInquiries();
    await server.api().listInquiries(status: InquiryStatus.answered);

    expect([for (final r in server.lists) r.url.queryParameters], [{}, {'status': 'answered'}]);
  });

  test('다음 쪽 열쇠는 마지막 줄의 created_at 원문 + id — has_more 가 거짓이면 null', () async {
    final server = server0()..pageSize = 2;

    final first = await server.api().listInquiries();

    expect(first.items.map((i) => i.id), [inquiryC, inquiryB]);
    expect(first.nextBefore, '2026-11-10T02:00:00+00:00|$inquiryB');
    final second = await server.api().listInquiries(before: first.nextBefore);
    expect(server.lists.last.url.queryParameters, {'before': '2026-11-10T02:00:00+00:00', 'before_id': inquiryB});
    expect(server.lists.last.url.toString(), contains('%2B00%3A00')); // "+" 가 공백으로 읽히지 않게 인코딩
    expect(second.items.map((i) => i.id), [inquiryA]);
    expect(second.nextBefore, isNull);
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
