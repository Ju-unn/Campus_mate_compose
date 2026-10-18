import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;

  AdminApi apiWith(http.Response Function(http.Request) respond, {String? token = 'tok'}) {
    requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
    return AdminApi('https://api.test/', client, () => token);
  }

  http.Response json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  test('로그인 토큰을 Bearer 로 달고 JSON 으로 주고받는다', () async {
    final api = apiWith((_) => json(200, {'nickname': '운영자'}));

    final response = await api.send('POST', '/admin/x', body: {'reason': '확인'});

    final request = requests.single;
    expect(request.url.toString(), 'https://api.test/admin/x');
    expect(request.headers['Authorization'], 'Bearer tok');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(request.body), {'reason': '확인'});
    expect(response.isSuccess, isTrue);
    expect(response.body, {'nickname': '운영자'});
  });

  test('me 는 GET /admin/me 를 부른다', () async {
    final api = apiWith((_) => json(200, {}));

    await api.me();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/admin/me');
  });

  test('403 본문의 detail 문자열을 이유로 읽는다(D0 확정 모양)', () async {
    final api = apiWith((_) => json(403, {'detail': AdminReason.notAdmin}));

    final response = await api.me();

    expect(response.statusCode, 403);
    expect(response.reason, AdminReason.notAdmin);
    expect(response.isSuccess, isFalse);
  });

  test('JSON 이 아닌 본문(게이트웨이 오류 페이지)도 예외 없이 상태코드만 돌려준다', () async {
    final api = apiWith((_) => http.Response('<html>bad gateway</html>', 502));

    final response = await api.me();

    expect(response.statusCode, 502);
    expect(response.body, isNull);
    expect(response.reason, isNull);
  });

  test('연결이 안 되면 상태코드 없이 돌려준다', () async {
    final api = apiWith((_) => throw http.ClientException('offline'));

    final response = await api.me();

    expect(response.statusCode, isNull);
    expect(response.isSuccess, isFalse);
  });

  test('세션이 없으면 요청을 보내지 않고 401 로 돌려준다', () async {
    final api = apiWith((_) => json(200, {}), token: null);

    final response = await api.me();

    expect(requests, isEmpty);
    expect(response.statusCode, 401);
  });
}
