import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/basic_info_repository.dart';
import 'package:campus_mate/profile/model/http_basic_info_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

/// 서버 계약(backend/app/profile_onboarding/router.py): POST /profile-onboarding/basic-info.
/// 가입용 번호 규칙에 걸리면 422 `{"detail": "올바른 휴대폰 번호를 입력해 주세요", "code": "phone_number_invalid"}`
/// (fix/onboarding-batch-server, 대장 전달 값).
void main() {
  late List<http.Request> requests;
  late http.Response Function() nextResponse;
  late HttpBasicInfoRepository repository;

  setUp(() {
    final auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    requests = [];
    nextResponse = () => http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
    final client = MockClient((request) async {
      requests.add(request);
      return nextResponse();
    });
    repository = HttpBasicInfoRepository(ApiClient('https://api.test', client, auth));
  });

  const submission = BasicInfoSubmission(
    nickname: '가나다',
    birthYear: 2002,
    heightCm: 175,
    phoneNumber: '01048217395',
    gender: 'male',
  );

  test('번호는 숫자만 phone_number 칸에 실어 보낸다', () async {
    await repository.submit(submission);

    expect(requests.single.url.path, '/profile-onboarding/basic-info');
    expect((jsonDecode(requests.single.body) as Map<String, dynamic>)['phone_number'], '01048217395');
  });

  test('422 phone_number_invalid 는 code 를 든 ServerRejectedFailure 다', () async {
    nextResponse = () => http.Response(
          jsonEncode({'detail': '올바른 휴대폰 번호를 입력해 주세요', 'code': 'phone_number_invalid'}),
          422,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    final result = await repository.submit(submission);

    final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
    expect(failure, isA<ServerRejectedFailure>());
    expect((failure! as ServerRejectedFailure).hasCode('phone_number_invalid'), isTrue);
    expect(failure.toDisplayMessage(), '올바른 휴대폰 번호를 입력해 주세요');
  });
}
