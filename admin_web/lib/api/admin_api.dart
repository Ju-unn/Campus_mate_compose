import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 서버 403 본문의 이유(설계서 §6-3). D0 확정 모양(대장 전달 10-18): `{"detail": "not_admin"}` · `{"detail": "mfa_required"}`
/// — `code` 칸 없이 detail 이 바로 이유 문자열이다. 401 의 detail 은 한국어 문구라 이유로 쓰지 않는다.
abstract final class AdminReason {
  static const String notAdmin = 'not_admin';
  static const String mfaRequired = 'mfa_required';
}

/// 응답 한 벌. [statusCode] 가 null 이면 연결 실패 · 시간 초과다.
class AdminApiResponse {
  const AdminApiResponse({this.statusCode, this.body, this.reason});

  final int? statusCode;

  /// JSON 으로 읽은 본문. 비었거나 JSON 이 아니면 null.
  final Object? body;

  /// 본문 `detail` 이 문자열이면 그 값. 403 에서만 [AdminReason] 으로 비교한다.
  final String? reason;

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

/// 관리자 서버(`/admin/*`)를 부르는 얇은 클라이언트. 앱 ApiClient 를 줄여 옮겼다(import 하지 않는다).
/// 실패를 예외로 던지지 않고 [AdminApiResponse] 로 돌려준다 — 화면이 로딩에서 멈추지 않게.
class AdminApi {
  AdminApi(String baseUrl, this._client, this._accessToken) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');

  final String _baseUrl;
  final http.Client _client;
  final String? Function() _accessToken;

  /// 끝내 오지 않는 조회를 끊는 시간(앱 http_send.dart 의 readTimeout 과 같은 값). 쓰기는 끊지 않는다 —
  /// 끊었다 다시 보내면 같은 조치가 두 번 갈 수 있다.
  static const Duration readTimeout = Duration(seconds: 15);

  Future<AdminApiResponse> me() => send('GET', '/admin/me');

  Future<AdminApiResponse> send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final token = _accessToken();
    if (token == null) {
      // 세션이 없으면 보내지 않는다 — 서버가 줄 답(401)과 같은 모양으로 돌려준다.
      return const AdminApiResponse(statusCode: 401);
    }
    final request = http.Request(method, _uri(path, query))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    try {
      final pending = _client.send(request).then(http.Response.fromStream);
      final response = await (method == 'GET' ? pending.timeout(readTimeout) : pending);
      final decoded = _decode(response.bodyBytes);
      return AdminApiResponse(statusCode: response.statusCode, body: decoded, reason: _reasonOf(decoded));
    } on Exception {
      // 연결 실패 · 시간 초과. 서버 500 은 CORS 헤더가 없어 브라우저에선 이쪽(ClientException)으로 온다(D0 안내).
      return const AdminApiResponse();
    }
  }

  Uri _uri(String path, Map<String, String>? query) {
    final url = Uri.parse('$_baseUrl$path');
    return query == null ? url : url.replace(queryParameters: query);
  }

  /// 서버가 charset 없이 JSON 을 보내도 한글이 깨지지 않게 바이트를 UTF-8 로 읽는다.
  static Object? _decode(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }

  static String? _reasonOf(Object? body) {
    if (body is! Map) return null;
    final detail = body['detail'];
    return detail is String ? detail : null;
  }
}
