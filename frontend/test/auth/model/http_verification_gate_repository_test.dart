import 'dart:convert';

import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/auth/model/http_verification_gate_repository.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockGoTrueClient auth;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpVerificationGateRepository buildRepository(http.Client client) {
    return HttpVerificationGateRepository(ApiClient('https://api.test', client, auth));
  }

  /// [consent] 를 null 로 두면 칸 자체가 없는 응답(동의 관문 전의 옛 서버)이다.
  /// [schoolEmailVerified] 도 null 이면 칸이 없다(학교 메일 관문 전의 옛 서버).
  Future<VerificationGate?> fetchGateWith(
    String status,
    bool hasSchoolInfo, {
    String? consent = 'current',
    bool? schoolEmailVerified,
  }) async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/me/verification-status');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return http.Response(
        jsonEncode({
          'status': status,
          'has_school_info': hasSchoolInfo,
          'consent': ?consent,
          'school_email_verified': ?schoolEmailVerified,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final result = await buildRepository(client).fetchGate();
    return result.when(onSuccess: (value) => value, onFailure: (_) => null);
  }

  test('동의 기록이 없으면 학생증보다 먼저 needsConsent', () async {
    final gate = await fetchGateWith('none', false, consent: 'none');

    expect(gate, VerificationGate.needsConsent);
  });

  test('옛 판에만 동의했으면 인증을 마친 계정도 needsConsentRenewal', () async {
    final gate = await fetchGateWith('verified', true, consent: 'outdated');

    expect(gate, VerificationGate.needsConsentRenewal);
  });

  test('consent 칸이 없는 옛 서버면 동의 관문 없이 지금 규칙 그대로', () async {
    // 서버가 먼저 나가는 게 순서지만, 거꾸로 되더라도 앱이 없는 POST 앞에 갇히지 않게 한다.
    final gate = await fetchGateWith('verified', true, consent: null);

    expect(gate, VerificationGate.complete);
  });

  test('학생증 인증 전이면 needsStudentVerification', () async {
    final gate = await fetchGateWith('pending', false);

    expect(gate, VerificationGate.needsStudentVerification);
  });

  test('인증은 됐지만 학교 정보가 없으면 needsSchoolInfo', () async {
    final gate = await fetchGateWith('verified', false);

    expect(gate, VerificationGate.needsSchoolInfo);
  });

  test('인증과 학교 정보가 모두 끝나면 complete', () async {
    final gate = await fetchGateWith('verified', true);

    expect(gate, VerificationGate.complete);
  });

  // 순서: 정지(헤더 · AuthRedirect) → 동의 → 학교 메일 → 학생증 → 학과와 학번. 한 줄이 응답 하나다.
  group('관문 순서(동의 > 학교 메일 > 학생증 > 학과)', () {
    const rows = <(String, bool?, String, bool, VerificationGate)>[
      // (consent, school_email_verified, status, has_school_info) → 관문
      ('none', false, 'none', false, VerificationGate.needsConsent),
      ('outdated', false, 'none', false, VerificationGate.needsConsentRenewal),
      ('current', false, 'none', false, VerificationGate.needsSchoolEmail),
      ('current', false, 'pending', false, VerificationGate.needsSchoolEmail),
      // 학생증까지 끝난 계정이어도 학교 메일이 없으면 학교 메일이 먼저다.
      ('current', false, 'verified', true, VerificationGate.needsSchoolEmail),
      ('current', true, 'none', false, VerificationGate.needsStudentVerification),
      ('current', true, 'verified', false, VerificationGate.needsSchoolInfo),
      ('current', true, 'verified', true, VerificationGate.complete),
    ];
    for (final (consent, schoolEmail, status, hasSchoolInfo, expected) in rows) {
      test('consent=$consent · school_email_verified=$schoolEmail · status=$status · has_school_info=$hasSchoolInfo → $expected',
          () async {
        final gate = await fetchGateWith(status, hasSchoolInfo, consent: consent, schoolEmailVerified: schoolEmail);

        expect(gate, expected);
      });
    }
  });

  test('school_email_verified 칸이 없는 옛 서버면 인증된 것으로 보고 학생증 관문으로', () async {
    // 칸이 없는데 미인증으로 보면 옛 서버에는 POST /school-email/verify 가 없어 02 에 갇힌다.
    final gate = await fetchGateWith('pending', false, schoolEmailVerified: null);

    expect(gate, VerificationGate.needsStudentVerification);
  });

  test('네트워크 연결이 끊기면 예외가 새지 않고 NetworkFailure', () async {
    final client = MockClient((request) async => throw Exception('연결 실패'));

    final result = await buildRepository(client).fetchGate();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
  });
}
