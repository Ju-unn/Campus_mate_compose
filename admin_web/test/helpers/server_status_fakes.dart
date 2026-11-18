import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/platform/confirm_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// pen A11 예시 시각: 마지막 갱신 22:41(한국) = 13:41 UTC. 칸은 19:45 ~ 22:40(한국) 36칸 — pen 첫 눈금 "20:00" 이 넷째 칸.
final DateTime checkedAtUtc = DateTime.utc(2026, 11, 17, 13, 41);
final DateTime firstBucketUtc = DateTime.utc(2026, 11, 17, 10, 45);

Map<String, Object?> anomalyRow(DateTime at, String kind, num value) => {'at': at.toIso8601String(), 'kind': kind, 'value': value};

/// 기본 이상 3줄(최신 순): 21:35 오류 비율 6% · 21:00 응답 느림 1.5초 · 20:05 서버 오류 3건(한국 시간)
List<Map<String, Object?>> defaultAnomalies() => [
  anomalyRow(DateTime.utc(2026, 11, 17, 12, 35), 'error_rate', 0.06),
  anomalyRow(DateTime.utc(2026, 11, 17, 12, 0), 'slow', 1500),
  anomalyRow(DateTime.utc(2026, 11, 17, 11, 5), 'errors', 3),
];

/// 서버 `/admin/server-status` 본문. 요청 수는 칸마다 200 안팎(pen 눈금 0/100/200/300), 서버 오류는 최대 9(눈금 0/5/10).
Map<String, Object?> serverStatusJson({List<Map<String, Object?>>? anomalies}) {
  return {
    'checked_at': '2026-11-17T22:41:00+09:00',
    'bucket_minutes': 5,
    'buckets': [
      for (var i = 0; i < 36; i++)
        {
          'start': firstBucketUtc.add(Duration(minutes: 5 * i)).toIso8601String(),
          'requests': 180 + (i * 37) % 70,
          'errors_5xx': const {3: 3, 10: 1, 15: 1, 22: 9, 28: 1}[i] ?? 0,
          'p50_ms': 160,
          'p95_ms': 1200,
          'instances': 1,
        },
    ],
    'now': {'requests_per_min': 42.0, 'error_rate': 0.002, 'p50_ms': 160, 'p95_ms': 1200, 'instances': 1},
    'anomalies': anomalies ?? defaultAnomalies(),
  };
}

/// 관문(/admin/me) · 서버 상태 · 대기 건수만 답하는 가짜. 그 밖 경로는 404(화면은 각자 오류로 그린다).
class FakeStatusServer {
  Map<String, Object?> status = serverStatusJson();
  Map<String, Object?> counts = {'heart_tasks': 0, 'graduates': 0, 'reports': 0, 'inquiries': 0};

  /// 0 이면 연결 실패, 그 밖은 그 상태코드
  int? statusFailure;

  /// 서버 상태를 이보다 많이 부르면 Error 를 던진다 — 관문 ↔ 배지 반복이 한 프레임 안에서 돌아 시험이 멈추지 않고 바로 FAIL 하게.
  /// Error 라 AdminApi.send(on Exception)가 삼키지 않고 반복 고리를 끊는다. null 이면 상한 없음.
  int? maxStatusCalls;

  /// 두 번째 관문 확인(/admin/me)부터의 상태코드 — 첫 번째는 늘 200(들어가기)
  int laterMeStatus = 200;
  int? countsFailure;

  /// 채우면 서버 상태 응답이 이것이 끝날 때까지 기다린다(새로고침 중 모습 확인)
  Completer<void>? holdStatus;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi('https://api.test', MockClient(_handle), () => 'token-test');

  int calls(String path) => requests.where((r) => r.url.path == path).length;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    switch (request.url.path) {
      case '/admin/me':
        return _json(calls('/admin/me') > 1 ? laterMeStatus : 200, const {});
      case '/admin/server-status':
        final limit = maxStatusCalls;
        if (limit != null && calls('/admin/server-status') > limit) throw StateError('서버 상태를 $limit번 넘게 불렀다(반복)');
        await holdStatus?.future;
        return _failOr(statusFailure, status);
      case '/admin/pending-counts':
        return _failOr(countsFailure, counts);
    }
    return _json(404, const {'detail': 'Not Found'});
  }

  static http.Response _failOr(int? failure, Object body) {
    if (failure == null) return _json(200, body);
    if (failure == 0) throw http.ClientException('offline');
    return _json(failure, const {'detail': 'auth_unavailable'});
  }

  static http.Response _json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);
}

/// 본 이상 열쇠("시각 UTC ISO|종류") — 저장소 칸의 값(JSON 배열)
String anomalyKeyOf(Map<String, Object?> row) {
  const names = {'errors': 'errors', 'error_rate': 'errorRate', 'slow': 'slow'};
  return '${DateTime.parse(row['at']! as String).toUtc().toIso8601String()}|${names[row['kind']]}';
}

/// 브라우저 저장소 대신 쓰는 칸
ConfirmStore memoryStore(Map<String, String> items) => ConfirmStore(readItem: (key) => items[key], writeItem: (key, value) => items[key] = value);

/// 시크릿 창 · 막힌 저장소처럼 읽기 · 쓰기가 모두 던진다
ConfirmStore throwingStore() => ConfirmStore(readItem: (_) => throw StateError('blocked'), writeItem: (_, _) => throw StateError('blocked'));
