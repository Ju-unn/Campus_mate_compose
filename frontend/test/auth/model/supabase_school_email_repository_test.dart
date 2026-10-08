import 'dart:convert';

import 'package:campus_mate/auth/model/supabase_school_email_repository.dart';
import 'package:campus_mate/auth/model/temporary_auth_connection.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

class MockAuthResponse extends Mock implements AuthResponse {}

void main() {
  setUpAll(() {
    registerFallbackValue(SignOutScope.local);
    registerFallbackValue(OtpType.email);
  });

  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;
  final code = VerificationCode.tryParse('123456')!;

  late MockGoTrueClient temporary;
  late MockGoTrueClient main;
  late List<http.Request> sent;
  late http.Response Function(http.Request) respond;

  SupabaseSchoolEmailRepository buildRepository() {
    final client = MockClient((request) async {
      sent.add(request);
      return respond(request);
    });
    return SupabaseSchoolEmailRepository(
      ApiClient('https://api.test', client, main),
      TemporaryAuthConnection(() => temporary),
    );
  }

  http.Response json(int status, Map<String, Object?> body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  Failure? failureOf<T>(Result<T> result) => result.when(onSuccess: (_) => null, onFailure: (f) => f);

  setUp(() {
    temporary = MockGoTrueClient();
    when(() => temporary.signOut(scope: any(named: 'scope'))).thenAnswer((_) async {});
    main = MockGoTrueClient();
    final mainSession = MockSession();
    when(() => mainSession.accessToken).thenReturn('main-token');
    when(() => main.currentSession).thenReturn(mainSession);
    sent = [];
    respond = (_) => json(200, {'ok': true});
  });

  group('requestCode', () {
    test('임시 연결로 학교 메일에 인증번호를 보내고 계정이 없으면 만든다', () async {
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenAnswer((_) async {});

      final result = await buildRepository().requestCode(email);

      expect(failureOf(result), isNull);
      verify(() => temporary.signInWithOtp(email: 'hong@snu.ac.kr', shouldCreateUser: true)).called(1);
      verifyNever(() => main.signInWithOtp(email: any(named: 'email')));
    });

    test('429 면 RateLimitedFailure — 같은 메일에 60초 안에 다시 보낸 경우', () async {
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenThrow(const AuthException('email rate limit', statusCode: '429', code: 'over_email_send_rate_limit'));

      final result = await buildRepository().requestCode(email);

      expect(failureOf(result), isA<RateLimitedFailure>());
    });

    test('가입 직전 훅이 거절하면(422) 서버 문구를 입력칸 아래 문구로 그대로 쓴다', () async {
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenThrow(const AuthException('허용되지 않은 학교 이메일이에요', statusCode: '422'));

      final failure = failureOf(await buildRepository().requestCode(email));

      expect(failure, isA<SignUpRejectedFailure>());
      expect(failure!.toDisplayMessage(), '허용되지 않은 학교 이메일이에요');
    });

    test('그 밖의 실패는 가르지 않고 "인증번호를 보내지 못했어요"', () async {
      for (final error in [
        const AuthException('hook failed', statusCode: '500'),
        AuthRetryableFetchException(message: 'network'),
      ]) {
        when(
          () => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')),
        ).thenThrow(error);

        final failure = failureOf(await buildRepository().requestCode(email));

        expect(failure, isA<CodeNotSentFailure>(), reason: '$error');
      }
    });
  });

  group('verifyCode', () {
    void verifyAnswers(Session? session) {
      final response = MockAuthResponse();
      when(() => response.session).thenReturn(session);
      when(
        () => temporary.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
      ).thenAnswer((_) async => response);
    }

    void verifyThrows(Object error) {
      when(
        () => temporary.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
      ).thenThrow(error);
    }

    test('임시 연결로 확인하고 임시 세션의 access_token 을 돌려준다', () async {
      final session = MockSession();
      when(() => session.accessToken).thenReturn('temp-token');
      verifyAnswers(session);

      final result = await buildRepository().verifyCode(email, code);

      expect(result.when(onSuccess: (token) => token, onFailure: (_) => null), 'temp-token');
      verify(() => temporary.verifyOTP(email: 'hong@snu.ac.kr', token: '123456', type: OtpType.email)).called(1);
      verifyNever(
        () => main.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: any(named: 'type')),
      );
    });

    test('틀린 코드 · 만료된 코드 · 코드 값 없는 403 은 WrongCodeFailure', () async {
      for (final error in [
        const AuthException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired'),
        const AuthException('Invalid login credentials', statusCode: '403', code: 'invalid_credentials'),
        const AuthException('Token has expired or is invalid', statusCode: '403'),
      ]) {
        verifyThrows(error);

        expect(failureOf(await buildRepository().verifyCode(email, code)), isA<WrongCodeFailure>(), reason: '$error');
      }
    });

    test('429 면 RateLimitedFailure', () async {
      verifyThrows(const AuthException('too many', statusCode: '429'));

      expect(failureOf(await buildRepository().verifyCode(email, code)), isA<RateLimitedFailure>());
    });

    test('코드 탓이 아닌 실패와 세션 없는 응답은 "학교 메일 인증을 마치지 못했어요"', () async {
      verifyThrows(const AuthException('User is banned', statusCode: '403', code: 'user_banned'));
      expect(failureOf(await buildRepository().verifyCode(email, code)), isA<SchoolEmailIncompleteFailure>());

      verifyThrows(AuthRetryableFetchException(message: 'network'));
      expect(failureOf(await buildRepository().verifyCode(email, code)), isA<SchoolEmailIncompleteFailure>());

      verifyAnswers(null);
      expect(failureOf(await buildRepository().verifyCode(email, code)), isA<SchoolEmailIncompleteFailure>());
    });
  });

  group('complete', () {
    test('메인(소셜) 토큰으로 인증한 POST /school-email/verify 에 임시 토큰을 싣는다', () async {
      final result = await buildRepository().complete('temp-token');

      expect(failureOf(result), isNull);
      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.toString(), 'https://api.test/school-email/verify');
      expect(sent.single.headers['Authorization'], 'Bearer main-token');
      expect(jsonDecode(sent.single.body), {'temp_access_token': 'temp-token'});
    });

    test('성공하면 임시 연결을 이 기기에서만 로그아웃해 비운다', () async {
      final repository = buildRepository();
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenAnswer((_) async {});
      await repository.requestCode(email);

      await repository.complete('temp-token');

      verify(() => temporary.signOut(scope: SignOutScope.local)).called(1);
    });

    test('실패해도 임시 연결을 비운다', () async {
      respond = (_) => json(403, {'detail': '학교 메일 인증이 끝나지 않았어요'});
      final repository = buildRepository();
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenAnswer((_) async {});
      await repository.requestCode(email);

      await repository.complete('temp-token');

      verify(() => temporary.signOut(scope: SignOutScope.local)).called(1);
    });

    test('403 이미 인증(SCHOOL_EMAIL_ALREADY_VERIFIED)은 성공과 같이 본다 — 게이트를 다시 읽으면 된다', () async {
      respond = (_) => json(403, {'detail': '이미 학교 메일 인증이 끝났어요'});

      expect(failureOf(await buildRepository().complete('temp-token')), isNull);
    });

    test('403 미확인(SCHOOL_EMAIL_NOT_CONFIRMED) · 503 · 네트워크는 "학교 메일 인증을 마치지 못했어요"', () async {
      for (final response in [
        () => json(403, {'detail': '학교 메일 인증이 끝나지 않았어요'}),
        () => json(503, {'detail': '잠시 뒤 다시 시도해 주세요'}),
        () => throw http.ClientException('network'),
      ]) {
        respond = (_) => response();

        final failure = failureOf(await buildRepository().complete('temp-token'));

        expect(failure, isA<SchoolEmailIncompleteFailure>());
        expect(failure!.toDisplayMessage(), '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요');
      }
    });

    test('422 두 가지는 서버 문구를 그대로 쓴다', () async {
      for (final message in ['등록되지 않은 학교 메일이에요', '재가입이 제한된 메일이에요']) {
        respond = (_) => json(422, {'detail': message});

        expect(failureOf(await buildRepository().complete('temp-token'))!.toDisplayMessage(), message);
      }
    });

    test('409 는 provider 로 어느 소셜 계정인지 알려 준다', () async {
      respond = (_) => json(409, {'detail': '이 메일은 카카오로 가입돼 있어요', 'provider': 'kakao'});

      final failure = failureOf(await buildRepository().complete('temp-token'));

      expect(failure, isA<SchoolEmailTakenFailure>());
      expect(failure!.toDisplayMessage(), '이 메일은 카카오로 가입돼 있어요');
      expect((failure as SchoolEmailTakenFailure).toHintMessage(), '카카오 계정으로 로그인해 주세요');
    });
  });
}
