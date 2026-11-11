import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String inquiryA = '00000000-0000-4000-8000-00000000000a';
const String inquiryB = '00000000-0000-4000-8000-00000000000b';
const String inquiryC = '00000000-0000-4000-8000-00000000000c';

/// 서버 문의 한 줄(backend/app/admin/inquiry_review.py `_item`) 모양. [profile] 을 null 로 주면 탈퇴한 사람의 문의다.
Map<String, Object?> inquiryRow(
  String id, {
  String reason = 'bug',
  String body = '앱이 멈춰요',
  String replyEmail = 'me@example.com',
  String status = 'new',
  String? adminMemo,
  String createdAt = '2026-11-10T01:00:00+00:00',
  String? answeredAt,
  Object? profile = const _Default(),
}) {
  return {
    'id': id,
    'reason': reason,
    'body': body,
    'reply_email': replyEmail,
    'status': status,
    'admin_memo': adminMemo,
    'created_at': createdAt,
    'updated_at': createdAt,
    'answered_at': answeredAt,
    'profile': profile is _Default ? {'id': 'p1', 'nickname': '하늘', 'university': '테스트대학교'} : profile,
  };
}

class _Default {
  const _Default();
}

/// 서버 대신 문의 목록 · 처리에 답한다. 목록은 서버처럼 최근 순 + (created_at, id) 커서 + `has_more`, 처리는 상태 · 메모만 바꾼다.
class FakeInquiryServer {
  FakeInquiryServer({List<Map<String, Object?>>? rows}) : rows = rows ?? [];

  List<Map<String, Object?>> rows;

  /// 쪽 크기(서버 기본은 50). 작게 줘서 "더 보기"를 시험한다.
  int pageSize = 50;

  /// 0 이면 연결 실패, 그 밖은 그 상태코드
  int? listFailure;
  int? patchFailure;
  Completer<void>? holdPatch;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi('https://api.test', MockClient(_handle), () => 'token-test');

  Iterable<http.Request> get lists => requests.where((r) => r.method == 'GET' && r.url.path == '/admin/inquiries');
  /// 관문이 로그인 판정에 부르는 `/admin/me` 요청들(관문이 다시 판정되면 늘어난다)
  Iterable<http.Request> get gateChecks => requests.where((r) => r.url.path == '/admin/me');
  Iterable<http.Request> get patches => requests.where((r) => r.method == 'PATCH');

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/admin/me') return _json(200, const {});
    if (path == '/admin/inquiries' && request.method == 'GET') return _list(request.url.queryParameters);
    if (path.startsWith('/admin/inquiries/') && request.method == 'PATCH') return _patch(path.split('/').last, request);
    return _json(404, const {'detail': 'Not Found'});
  }

  http.Response _list(Map<String, String> query) {
    final failure = listFailure;
    if (failure != null) return failure == 0 ? throw http.ClientException('offline') : _json(failure, const {});
    final status = query['status'];
    final sorted = rows.where((row) => status == null || row['status'] == status).toList()
      ..sort((a, b) {
        final byTime = (b['created_at']! as String).compareTo(a['created_at']! as String);
        return byTime != 0 ? byTime : (b['id']! as String).compareTo(a['id']! as String);
      });
    var from = 0;
    final beforeId = query['before_id'];
    if (beforeId != null) from = sorted.indexWhere((row) => row['id'] == beforeId && row['created_at'] == query['before']) + 1;
    final slice = sorted.skip(from).take(pageSize + 1).toList();
    return _json(200, {'items': slice.take(pageSize).toList(), 'has_more': slice.length > pageSize});
  }

  Future<http.Response> _patch(String id, http.Request request) async {
    await holdPatch?.future;
    final failure = patchFailure;
    if (failure != null) return failure == 0 ? throw http.ClientException('offline') : _json(failure, const {'detail': 'not_found'});
    final row = rows.firstWhere((row) => row['id'] == id);
    final body = jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>;
    if (body.containsKey('status')) row['status'] = body['status'];
    if (body.containsKey('admin_memo')) {
      final memo = (body['admin_memo'] as String?)?.trim();
      row['admin_memo'] = memo == null || memo.isEmpty ? null : memo;
    }
    row['answered_at'] = row['status'] == 'answered' ? (row['answered_at'] ?? '2026-11-10T09:00:00+00:00') : null;
    return _json(200, row);
  }

  static http.Response _json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);
}
