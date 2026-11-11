import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/profile/basic/model/data/basic_info_submission.dart';
import 'package:campus_mate/profile/basic/model/repository/http_basic_info_repository.dart';
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
    phoneNumber: '01001352468',
    gender: 'male',
  );

  test('번호는 숫자만 phone_number 칸에 실어 보낸다', () async {
    await repository.submit(submission);

    expect(requests.single.url.path, '/profile-onboarding/basic-info');
    expect((jsonDecode(requests.single.body) as Map<String, dynamic>)['phone_number'], '01001352468');
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
    expect(failureText(AppLocalizationsKo(), failure), '올바른 휴대폰 번호를 입력해 주세요');
  });

  // 서버 계약(PR #694 backend/app/phone_verification/router.py): POST /phone-verification/send · /verify.
  group('휴대폰 문자 인증', () {
    test('인증번호 받기는 번호를 숫자만 phone_number 칸에 실어 보낸다', () async {
      nextResponse = () => http.Response(
            jsonEncode({'resend_after_seconds': 60, 'expires_in_seconds': 180, 'already_sent': false}),
            200,
          );

      await repository.sendPhoneCode('01001352468');

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/phone-verification/send');
      expect(jsonDecode(requests.single.body), {'phone_number': '01001352468'});
    });

    test('받기 응답의 초 두 개와 already_sent 를 읽는다', () async {
      nextResponse = () => http.Response(
            jsonEncode({'resend_after_seconds': 37, 'expires_in_seconds': 157, 'already_sent': true}),
            200,
          );

      final sent = (await repository.sendPhoneCode('01001352468')).when(onSuccess: (s) => s, onFailure: (_) => null)!;

      expect(sent.resendAfter, const Duration(seconds: 37));
      expect(sent.expiresIn, const Duration(seconds: 157));
      expect(sent.alreadySent, isTrue);
    });

    test('받기 응답의 모양이 다르면 UnknownFailure 다', () async {
      nextResponse = () => http.Response(jsonEncode({'resend_after_seconds': '60'}), 200);

      final failure = (await repository.sendPhoneCode('01001352468')).when(onSuccess: (_) => null, onFailure: (f) => f);

      expect(failure, isA<UnknownFailure>());
    });

    test('받기 429 는 retry_after_seconds 를 든 RateLimitedFailure 다', () async {
      nextResponse = () => http.Response(
            jsonEncode({'detail': 'limited', 'code': 'phone_verification_rate_limited', 'retry_after_seconds': 3600}),
            429,
          );

      final failure = (await repository.sendPhoneCode('01001352468')).when(onSuccess: (_) => null, onFailure: (f) => f);

      expect(failure, isA<RateLimitedFailure>().having((f) => f.retryAfterSeconds, 'retryAfterSeconds', 3600));
    });

    test('확인은 번호와 인증번호를 실어 보내고 200 이면 성공이다', () async {
      nextResponse = () => http.Response(jsonEncode({'verified': true}), 200);

      final result = await repository.verifyPhoneCode('01001352468', '482915');

      expect(requests.single.url.path, '/phone-verification/verify');
      expect(jsonDecode(requests.single.body), {'phone_number': '01001352468', 'code': '482915'});
      expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    });

    test('확인 400 phone_code_mismatch 는 남은 기회를 든 ServerRejectedFailure 다', () async {
      nextResponse = () => http.Response(
            jsonEncode({'detail': 'mismatch', 'code': 'phone_code_mismatch', 'remaining_attempts': 3}),
            400,
          );

      final failure = (await repository.verifyPhoneCode('01001352468', '000000'))
          .when(onSuccess: (_) => null, onFailure: (f) => f)! as ServerRejectedFailure;

      expect(failure.hasCode('phone_code_mismatch'), isTrue);
      expect(failure.remainingAttempts, 3);
    });
  });
}
