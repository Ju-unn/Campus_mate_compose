import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// FastAPI 를 부르는 모든 Repository 가 공유하는 한 벌. 예전에는 저장소 15개가 각자
/// `baseUrl · http.Client · GoTrueClient` 셋을 들고 `sendAuthorizedRequest` 와
/// `Authorization` 헤더 조립을 똑같이 되풀이했다 — 그 몫을 여기로 옮겼다.
///
/// 상태코드 분류와 세션 확인은 여전히 [sendAuthorizedRequest] 가 한다. 이 클래스는
/// URL 을 붙이고, 헤더를 달고, 본문을 JSON 으로 싸고, 응답을 파싱할 뿐이다.
class ApiClient {
  const ApiClient(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  Uri uri(String path, [Map<String, String>? query]) {
    final url = Uri.parse('$_baseUrl$path');
    return query == null ? url : url.replace(queryParameters: query);
  }

  /// JSON 한 번 주고받는 흔한 경우. [parse] 는 성공 응답의 본문만 받는다 —
  /// 돌려줄 것이 없으면 `(_) {}` 로 비워 둔다.
  Future<Result<T>> send<T>(
    String method,
    String path,
    T Function(Object body) parse, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final result = await sendRequest((accessToken) {
      final request = http.Request(method, uri(path, query))
        ..headers['Authorization'] = 'Bearer $accessToken';
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body);
      }
      return request;
    });
    return result.when(
      // 본문 없이 성공만 알려주는 엔드포인트가 있다(예: POST /school-info).
      // 빈 문자열을 jsonDecode 하면 FormatException 이라 그 전에 걸러 낸다.
      onSuccess: (response) => Success(
        parse(response.body.isEmpty ? const <String, dynamic>{} : jsonDecode(response.body)),
      ),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  /// 사진을 올리는 두 곳(학생증 3b · 프로필 사진 04-2)이 쓴다. 둘 다 파일 칸 이름이 `photo` 다.
  /// 예전에는 저장소가 각자 `Authorization` 을 달았다 — 그 한 줄을 여기로 모았다(조각 4 리뷰 권고 4번).
  Future<Result<http.Response>> sendMultipart(
    String path,
    Map<String, String> fields,
    String photoPath,
  ) =>
      sendRequest((accessToken) async => http.MultipartRequest('POST', uri(path))
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..fields.addAll(fields)
        ..files.add(await http.MultipartFile.fromPath('photo', photoPath)));

  /// 위 두 가지에 들지 않는 요청이 쓴다. 헤더는 부른 쪽이 단다.
  Future<Result<http.Response>> sendRequest(
    FutureOr<http.BaseRequest> Function(String accessToken) buildRequest,
  ) =>
      sendAuthorizedRequest(_client, _auth, buildRequest);
}
