import 'dart:convert';

import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/http_acquisition_repository.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

/// 서버 계약(backend/app/profile_onboarding/router.py): POST /profile-onboarding/acquisition
/// `{"channel", "note"}` → `{"ok": true}`. channel 값은 enum 이름 그대로다.
void main() {
  late List<http.Request> requests;
  late HttpAcquisitionRepository repository;

  setUp(() {
    final auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
    });
    repository = HttpAcquisitionRepository(ApiClient('https://api.test', client, auth));
  });

  test('칩 값은 enum 이름 그대로, 기타 글은 note 로 보낸다', () async {
    final result = await repository.submit(AcquisitionChannel.other, '학교 축제');

    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/profile-onboarding/acquisition');
    expect(jsonDecode(requests.single.body), {'channel': 'other', 'note': '학교 축제'});
  });

  test('기타가 아니면 note 는 null 로 보낸다', () async {
    await repository.submit(AcquisitionChannel.everytime, null);

    expect(jsonDecode(requests.single.body), {'channel': 'everytime', 'note': null});
  });
}
