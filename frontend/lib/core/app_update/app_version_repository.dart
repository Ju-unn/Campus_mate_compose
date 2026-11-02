import 'dart:convert';

import 'package:campus_mate/core/app_update/app_version.dart';
import 'package:http/http.dart' as http;

/// 서버가 정한 최소 앱 버전을 묻는다(`GET /app/version`, 백엔드 `app_version/router.py`).
///
/// 로그인 전 시작 때도 부르므로 `ApiClient`(세션이 없으면 요청을 만들지 않는다)를 쓰지 않고 인증 헤더 없이 직접 보낸다.
class AppVersionRepository {
  const AppVersionRepository(this._baseUrl, this._client);

  final String _baseUrl;
  final http.Client _client;

  /// 응답이 이만큼 안 오면 포기한다 — 시작이 서버 응답을 오래 기다리지 않게. 서버의 콜드 스타트 11초는 기다리지 않는다.
  static const Duration _timeout = Duration(seconds: 3);

  /// 서버가 정한 최소 버전. **어떤 이유로든 알아내지 못하면 null** — 서버가 안 정함 · 오류 응답 · 연결 실패 · 시간 초과 ·
  /// 이상한 모양 모두 같다. null 은 "막지 않음"이라 서버 장애가 앱 잠금으로 번지지 않는다.
  Future<AppVersion?> fetchMinimum() async {
    try {
      final response = await _client.get(Uri.parse('$_baseUrl/app/version')).timeout(_timeout);
      return response.statusCode == 200 ? _minimumIn(response.body) : null;
    } on Exception {
      // 연결 실패 · 시간 초과(TimeoutException) · JSON 이 아님(FormatException) 모두 알아내지 못한 경우다.
      return null;
    }
  }

  AppVersion? _minimumIn(String body) {
    final decoded = jsonDecode(body);
    final minimum = decoded is Map<String, Object?> ? decoded['min_version'] : null;
    return minimum is String ? AppVersion.tryParse(minimum) : null;
  }
}
