import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/server_status/server_status_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 서버 상태 · 대기 건수 API(backend/app/admin/server_status.py · stats.py get_pending_counts 의 응답 모양)
void main() {
  late List<http.Request> requests;

  AdminApi apiReturning(int status, Object body) {
    requests = [];
    return AdminApi('https://api.test', MockClient((request) async {
      requests.add(request);
      return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
    }), () => 'token-test');
  }

  final statusBody = {
    'checked_at': '2026-11-17T22:41:00+09:00',
    'bucket_minutes': 5,
    'buckets': [
      {'start': '2026-11-17T13:35:00+00:00', 'requests': 120, 'errors_5xx': 2, 'p50_ms': 160, 'p95_ms': 1200, 'instances': 1},
      {'start': '2026-11-17T13:40:00+00:00', 'requests': 0, 'errors_5xx': 0, 'p50_ms': null, 'p95_ms': null, 'instances': null},
    ],
    'now': {'requests_per_min': 42.0, 'error_rate': 0.002, 'p50_ms': 160, 'p95_ms': 1200, 'instances': 1},
    'anomalies': [
      {'at': '2026-11-17T12:35:00+00:00', 'kind': 'error_rate', 'value': 0.06},
      {'at': '2026-11-17T12:30:00+00:00', 'kind': 'unknown', 'value': 1},
      {'at': '2026-11-17T11:00:00+00:00', 'kind': 'errors', 'value': 3},
      {'at': '2026-11-17T10:00:00+00:00', 'kind': 'slow', 'value': 1500},
    ],
  };

  test('GET /admin/server-status 를 읽어 칸 · 지금 숫자 · 이상 목록으로', () async {
    final api = apiReturning(200, statusBody);

    final status = await api.serverStatus();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/admin/server-status');
    expect(status.checkedAt, DateTime.utc(2026, 11, 17, 13, 41));
    expect(status.buckets.length, 2);
    final first = status.buckets.first;
    expect((first.start, first.requests, first.errors5xx, first.p50Ms, first.p95Ms, first.instances), (DateTime.utc(2026, 11, 17, 13, 35), 120, 2, 160, 1200, 1));
    final empty = status.buckets.last;
    expect((empty.p50Ms, empty.p95Ms, empty.instances), (null, null, null));
    expect((status.now.requestsPerMin, status.now.errorRate, status.now.p50Ms, status.now.p95Ms, status.now.instances), (42.0, 0.002, 160, 1200, 1));
  });

  test('이상 줄: 모르는 kind 는 버리고 나머지는 서버 순서(최신 순) 그대로', () async {
    final status = await apiReturning(200, statusBody).serverStatus();

    expect([for (final a in status.anomalies) a.kind], [AnomalyKind.errorRate, AnomalyKind.errors, AnomalyKind.slow]);
    expect(status.anomalies.first.at, DateTime.utc(2026, 11, 17, 12, 35));
    expect([for (final a in status.anomalies) a.value], [0.06, 3, 1500]);
  });

  test('지금 숫자가 비면(null) null — 정수로 온 비율 0 도 읽는다', () async {
    final body = {
      ...statusBody,
      'now': {'requests_per_min': 0, 'error_rate': 0, 'p50_ms': null, 'p95_ms': null, 'instances': null},
    };
    final status = await apiReturning(200, body).serverStatus();

    expect((status.now.requestsPerMin, status.now.errorRate, status.now.p50Ms, status.now.p95Ms, status.now.instances), (0.0, 0.0, null, null, null));
  });

  test('503(구글 못 읽음)은 AdminApiFailure(503), 모양이 틀린 본문도 실패', () async {
    await expectLater(apiReturning(503, {'detail': 'x'}).serverStatus(), throwsA(isA<AdminApiFailure>().having((f) => f.statusCode, 'status', 503)));
    await expectLater(apiReturning(200, {'wrong': 1}).serverStatus(), throwsA(isA<AdminApiFailure>()));
  });

  test('GET /admin/pending-counts → 메뉴별 대기 건수', () async {
    final api = apiReturning(200, {'heart_tasks': 2, 'graduates': 1, 'reports': 3, 'inquiries': 4});

    final counts = await api.pendingCounts();

    expect(requests.single.url.path, '/admin/pending-counts');
    expect((counts.heartTasks, counts.graduates, counts.reports, counts.inquiries), (2, 1, 3, 4));
    await expectLater(apiReturning(200, {'heart_tasks': 'x'}).pendingCounts(), throwsA(isA<AdminApiFailure>()));
  });
}
