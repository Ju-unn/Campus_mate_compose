import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 1×1 투명 PNG — 코드에서 만든 바이트(실제 사진이 아니다)
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// 서버 공지 한 줄(backend/app/admin/notices.py `_view`) 모양
Map<String, Object?> noticeRow(
  String id, {
  String title = '공지 제목',
  String text = '공지 본문',
  String? imageUrl,
  String status = 'visible',
  String createdAt = '2026-11-24T01:00:00.123456+00:00',
}) {
  return {'id': id, 'title': title, 'text': text, 'image_url': imageUrl, 'status': status, 'created_at': createdAt};
}

/// 서버 대신 `/admin/notices` 에 답한다. 목록은 서버처럼 최근 순(created_at · id 내림) 20개씩 + 커서(before · before_id),
/// 만들기는 맨 앞에 한 줄을 더하고, 지우기는 그 줄을 뺀다. 실패 상태코드 칸에 0 을 넣으면 연결 실패(ClientException)다.
class FakeNoticeServer {
  FakeNoticeServer({List<Map<String, Object?>>? rows}) : rows = rows ?? [];

  List<Map<String, Object?>> rows;

  int? listFailure;

  /// [더 보기](커서 있는 목록 요청)만 붙잡는다 — 첫 쪽 다시 받기는 그대로 답한다(늦게 온 응답 시험)
  Completer<void>? holdMore;

  /// [더 보기]만 실패(붙잡았다 풀린 뒤에 본다)
  int? moreFailure;
  int? createFailure;

  /// 만들기 실패의 detail(그림 오류 image_type · image_too_large)
  String? createReason;
  int? deleteFailure;
  Completer<void>? holdCreate;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi('https://api.test', MockClient(_handle), () => 'token-test');

  Iterable<http.Request> get lists => requests.where((r) => r.method == 'GET' && r.url.path == '/admin/notices');
  Iterable<http.Request> get creates => requests.where((r) => r.method == 'POST' && r.url.path == '/admin/notices');
  Iterable<http.Request> get deletes => requests.where((r) => r.method == 'DELETE');

  /// multipart 본문을 글자로(그림 바이트는 깨진 글자로 보인다 — 칸 이름 · 글 칸 값만 본다)
  static String formText(http.Request request) => utf8.decode(request.bodyBytes, allowMalformed: true);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/admin/me') return _json(200, const {});
    if (path == '/admin/notices' && request.method == 'GET') {
      final query = request.url.queryParameters;
      if (query.containsKey('before')) {
        await holdMore?.future;
        final failure = moreFailure;
        if (failure != null) return _json(failure, const {});
      }
      return _list(query);
    }
    if (path == '/admin/notices' && request.method == 'POST') return _create(request);
    if (path.startsWith('/admin/notices/') && request.method == 'DELETE') return _delete(path.split('/').last);
    return _json(404, const {'detail': 'Not Found'});
  }

  http.Response _list(Map<String, String> query) {
    final failure = listFailure;
    if (failure != null) return failure == 0 ? throw http.ClientException('offline') : _json(failure, const {});
    final sorted = [...rows]..sort((a, b) => _key(b).compareTo(_key(a)));
    final before = query['before'];
    final after = before == null ? sorted : sorted.where((row) => _key(row).compareTo('$before|${query['before_id']}') < 0);
    final page = after.take(21).toList();
    return _json(200, {'items': page.take(20).toList(), 'has_more': page.length > 20});
  }

  static String _key(Map<String, Object?> row) => '${row['created_at']}|${row['id']}';

  Future<http.Response> _create(http.Request request) async {
    await holdCreate?.future;
    final failure = createFailure;
    if (failure != null) {
      return failure == 0 ? throw http.ClientException('offline') : _json(failure, {'detail': createReason ?? 'failed'});
    }
    final id = 'n-new-${creates.length}';
    rows.add(noticeRow(id, title: '새 공지', createdAt: '2026-11-25T00:00:00+00:00'));
    return _json(201, {'id': id});
  }

  http.Response _delete(String id) {
    final failure = deleteFailure;
    if (failure != null) return failure == 0 ? throw http.ClientException('offline') : _json(failure, const {});
    rows.removeWhere((row) => row['id'] == id);
    return _json(200, {'id': id});
  }

  static http.Response _json(int status, Object body) {
    return http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});
  }
}
