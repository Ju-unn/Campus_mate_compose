import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/list_page.dart';
import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:campus_mate_admin/inquiries/inquiry_item.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 목록 11개는 모두 번호 쪽(page · size)으로 받고 `{items, total, page, size}` 를 읽는다(서버 backend/app/admin/*).
void main() {
  late List<http.Request> requests;
  late Object body;

  AdminApi api() {
    requests = <http.Request>[];
    return AdminApi('https://api.test', MockClient((request) async {
      requests.add(request);
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    }), () => 'tok');
  }

  setUp(() => body = {'items': <Object?>[], 'total': 57, 'page': 3, 'size': 20});

  final calls = <String, Future<ListPage<Object?>> Function(AdminApi api, int page)>{
    '/admin/users': (a, p) => a.listUsers(page: p),
    '/admin/reports': (a, p) => a.listReports(page: p),
    '/admin/heart-tasks': (a, p) => a.listHeartTasks(page: p),
    '/admin/graduate-requests': (a, p) => a.listGraduateRequests(page: p),
    '/admin/inquiries': (a, p) => a.listInquiries(page: p),
    '/admin/matching/pairs': (a, p) => a.matchingPairs(page: p),
    '/admin/matching/requests': (a, p) => a.matchingRequests(page: p),
    '/admin/actions': (a, p) => a.listActions(page: p),
    '/admin/unknown-domains': (a, p) => a.unknownDomains(page: p),
    '/admin/billing/shortfall': (a, p) => a.billingShortfall(page: p),
    '/admin/billing/frequent-returns': (a, p) => a.billingReturnedAccounts(page: p),
  };

  for (final MapEntry(key: path, value: call) in calls.entries) {
    test('$path: page · size(20) 를 쿼리로 보내고 total 을 읽는다', () async {
      final client = api();
      final page = await call(client, 3);
      expect(requests.single.url.path, path);
      expect(requests.single.url.queryParameters, containsPair('page', '3'));
      expect(requests.single.url.queryParameters, containsPair('size', '${AdminApi.pageSize}'));
      expect(AdminApi.pageSize, 20);
      expect(page.items, isEmpty);
      expect(page.total, 57);
    });

    test('$path: total 이 없으면 모양 오류(AdminApiFailure)', () async {
      body = {'items': <Object?>[]};
      await expectLater(call(api(), 1), throwsA(isA<AdminApiFailure>()));
    });
  }

  test('필터는 쪽과 함께 간다', () async {
    final client = api();
    await client.listReports(status: ReportStatus.dismissed, page: 2);
    await client.listInquiries(status: InquiryStatus.answered);
    await client.listGraduateRequests(status: GraduateStatus.rejected);
    expect([for (final r in requests) r.url.queryParameters], [
      {'status': 'dismissed', 'page': '2', 'size': '20'},
      {'status': 'answered', 'page': '1', 'size': '20'},
      {'status': 'rejected', 'page': '1', 'size': '20'},
    ]);
  });
}
