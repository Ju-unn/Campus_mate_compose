import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/model/http_graduate_verification_repository.dart';
import 'package:campus_mate/graduate/model/previous_school_email.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockGoTrueClient auth;
  late Directory tempDir;
  late File photo;

  setUp(() async {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    tempDir = Directory.systemTemp.createTempSync('graduate_repo_test');
    photo = File('${tempDir.path}/certificate.jpg');
    await photo.writeAsBytes([0xFF, 0xD8, 0xFF]);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  HttpGraduateVerificationRepository build(http.Client client) =>
      HttpGraduateVerificationRepository(ApiClient('https://api.test', client, auth));

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  Failure? failureOf<T>(Result<T> result) => result.when(onSuccess: (_) => null, onFailure: (failure) => failure);

  group('chooseMethod', () {
    test('PUT /me/verification-method 에 서버 문자열을 보낸다', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return json({'verification_method': 'graduate_certificate', 'cancelled_request': false});
      });

      final result = await build(client).chooseMethod(VerificationMethod.graduateCertificate);

      expect(failureOf(result), isNull);
      expect(seen.method, 'PUT');
      expect(seen.url.toString(), 'https://api.test/me/verification-method');
      expect(seen.headers['Authorization'], 'Bearer token-abc');
      expect(jsonDecode(seen.body), {'method': 'graduate_certificate'});
    });

    test('뒤로가기는 method 를 null 로 보낸다 — 칸 자체는 남는다', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return json({'verification_method': null, 'cancelled_request': false});
      });

      await build(client).chooseMethod(null);

      expect(jsonDecode(seen.body), {'method': null});
    });

    test('403 graduate_disabled · 409 already_verified 는 서버 코드를 단 실패다', () async {
      final disabled = await build(MockClient((_) async => json({'detail': '지금은 졸업생 인증을 받지 않아요', 'code': 'graduate_disabled'}, 403)))
          .chooseMethod(VerificationMethod.graduateCertificate);
      final verified = await build(MockClient((_) async => json({'detail': '이미 인증이 끝났어요', 'code': 'already_verified'}, 409)))
          .chooseMethod(null);

      expect((failureOf(disabled)! as ServerRejectedFailure).hasCode('graduate_disabled'), isTrue);
      expect((failureOf(verified)! as ServerRejectedFailure).hasCode('already_verified'), isTrue);
    });

    test('인터넷이 없으면 NetworkFailure', () async {
      final result = await build(MockClient((_) async => throw Exception('연결 실패'))).chooseMethod(null);

      expect(failureOf(result), isA<NetworkFailure>());
    });
  });

  group('submit', () {
    test('photo 칸과 agreed=true 를 multipart 로 보내고, 이메일이 없으면 그 칸 자체가 없다', () async {
      late http.BaseRequest seen;
      late String body;
      final client = MockClient((request) async {
        seen = request;
        body = latin1.decode(request.bodyBytes);
        return json({'state': 'pending', 'attempts_left': 2}, 201);
      });

      final result = await build(client).submit(photo, null);

      expect(failureOf(result), isNull);
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.test/graduate-verification');
      expect(seen.headers['content-type'], startsWith('multipart/form-data'));
      expect(body, contains('name="photo"'));
      expect(body, contains('name="agreed"'));
      expect(body, contains('true'));
      expect(body, isNot(contains('previous_school_email')));
    });

    test('이전 학교 메일이 있으면 요청 값(소문자·공백 뗌)으로 싣는다', () async {
      late String body;
      final client = MockClient((request) async {
        body = latin1.decode(request.bodyBytes);
        return json({'state': 'pending', 'attempts_left': 1}, 201);
      });

      await build(client).submit(photo, PreviousSchoolEmail.tryParse(' Old@Univ.ac.kr '));

      expect(body, contains('name="previous_school_email"'));
      expect(body, contains('old@univ.ac.kr'));
    });

    test('201 이면 대기 상태와 남은 횟수를 돌려준다', () async {
      final client = MockClient((_) async => json({'state': 'pending', 'attempts_left': 2}, 201));

      final result = await build(client).submit(photo, null);

      final state = result.when(onSuccess: (state) => state, onFailure: (_) => null);
      expect(state, isA<GraduatePending>());
      expect((state! as GraduatePending).attemptsLeft, 2);
    });

    test('약속과 다른 성공 본문이면 예외가 새지 않고 UnknownFailure', () async {
      final client = MockClient((_) async => json({'unexpected': true}, 201));

      final result = await build(client).submit(photo, null);

      expect(failureOf(result), isA<UnknownFailure>());
    });

    test('서버 오류가 구분된다: 429 · 409 · 400', () async {
      final exhausted = await build(MockClient((_) async => json({'detail': '신청 횟수를 모두 썼어요, 문의해 주세요', 'code': 'attempts_exhausted'}, 429)))
          .submit(photo, null);
      final pending = await build(MockClient((_) async => json({'detail': '이미 심사 중이에요, 결과를 기다려 주세요', 'code': 'already_pending'}, 409)))
          .submit(photo, null);
      final consent = await build(MockClient((_) async => json({'detail': '개인정보 수집에 동의해 주세요', 'code': 'consent_required'}, 400)))
          .submit(photo, null);

      expect(failureOf(exhausted), isA<RateLimitedFailure>());
      expect(failureOf(exhausted)!.toDisplayMessage(), '신청 횟수를 모두 썼어요, 문의해 주세요');
      expect((failureOf(pending)! as ServerRejectedFailure).hasCode('already_pending'), isTrue);
      expect((failureOf(consent)! as ServerRejectedFailure).hasCode('consent_required'), isTrue);
    });
  });

  group('fetchState', () {
    Future<GraduateRequestState?> fetchWith(Map<String, Object?> body) async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://api.test/me/verification-status');
        return json(body);
      });
      final result = await build(client).fetchState();
      return result.when(onSuccess: (state) => state, onFailure: (_) => fail('성공해야 한다'));
    }

    test('graduate 칸의 반려를 사유와 남은 횟수로 읽는다', () async {
      final state = await fetchWith({
        'consent': 'current',
        'graduate': {'state': 'rejected', 'reject_reason': 'unreadable', 'attempts_left': 1, 'submitted_at': null},
      });

      final rejected = state! as GraduateRejected;
      expect(rejected.reason, GraduateRejectReason.unreadable);
      expect(rejected.attemptsLeft, 1);
    });

    test('graduate 칸이 null 이거나 없으면(옛 서버 포함) null', () async {
      expect(await fetchWith({'graduate': null}), isNull);
      expect(await fetchWith({'consent': 'current'}), isNull);
    });
  });
}
