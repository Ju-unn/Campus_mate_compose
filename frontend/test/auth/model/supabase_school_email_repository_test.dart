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
          .thenThrow(const AuthException('등록되지 않은 학교 메일이에요', statusCode: '422'));

      final failure = failureOf(await buildRepository().requestCode(email));

      expect(failure, isA<SignUpRejectedFailure>());
      expect(failure!.toDisplayMessage(), '등록되지 않은 학교 메일이에요');
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
    Future<SupabaseSchoolEmailRepository> openedRepository() async {
      final repository = buildRepository();
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenAnswer((_) async {});
      await repository.requestCode(email);
      return repository;
    }

    test('메인(소셜) 토큰으로 인증한 POST /school-email/verify 에 임시 토큰을 싣는다', () async {
      final result = await buildRepository().complete('temp-token');

      expect(failureOf(result), isNull);
      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.toString(), 'https://api.test/school-email/verify');
      expect(sent.single.headers['Authorization'], 'Bearer main-token');
      expect(jsonDecode(sent.single.body), {'temp_access_token': 'temp-token'});
    });

    // 서버(#426)가 코드 있는 오류마다 `code` 를 싣는다. 문구가 달라도 code 로 가른다.
    group('code 가 있으면 code 로 가른다', () {
      test('SCHOOL_EMAIL_ALREADY_VERIFIED 는 문구가 달라도 성공과 같이 본다', () async {
        respond = (_) => json(403, {'detail': '다른 문구', 'code': 'SCHOOL_EMAIL_ALREADY_VERIFIED'});

        expect(failureOf(await buildRepository().complete('temp-token')), isNull);
      });

      test('SCHOOL_EMAIL_NOT_CONFIRMED 는 문구가 달라도 SchoolEmailNotConfirmedFailure', () async {
        respond = (_) => json(403, {'detail': '다른 문구', 'code': 'SCHOOL_EMAIL_NOT_CONFIRMED'});

        final failure = failureOf(await buildRepository().complete('temp-token'));

        expect(failure, isA<SchoolEmailNotConfirmedFailure>());
        expect(failure!.toDisplayMessage(), '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요');
      });

      test('DOMAIN_NOT_ALLOWED · REJOIN_BLOCKED 는 서버 문구를 그대로 담은 SchoolEmailRejectedFailure', () async {
        for (final (code, message) in [
          ('SCHOOL_EMAIL_DOMAIN_NOT_ALLOWED', '등록되지 않은 학교 메일이에요'),
          ('SCHOOL_EMAIL_REJOIN_BLOCKED', '재가입이 제한된 메일이에요'),
        ]) {
          respond = (_) => json(422, {'detail': message, 'code': code});

          final failure = failureOf(await buildRepository().complete('temp-token'));

          expect(failure, isA<SchoolEmailRejectedFailure>(), reason: code);
          expect(failure!.toDisplayMessage(), message, reason: code);
        }
      });

      test('SCHOOL_EMAIL_TAKEN + provider 는 SchoolEmailTakenFailure', () async {
        respond = (_) => json(409, {'detail': '이 메일은 카카오로 가입돼 있어요', 'code': 'SCHOOL_EMAIL_TAKEN', 'provider': 'kakao'});

        final failure = failureOf(await buildRepository().complete('temp-token'));

        expect(failure, isA<SchoolEmailTakenFailure>());
        expect((failure! as SchoolEmailTakenFailure).toHintMessage(), '카카오 계정으로 로그인해 주세요');
      });

      test('AUTH_UNAVAILABLE(503) 는 다시 하라는 문구', () async {
        respond = (_) => json(503, {'detail': '잠시 뒤 다시 시도해 주세요', 'code': 'AUTH_UNAVAILABLE'});

        expect(failureOf(await buildRepository().complete('temp-token')), isA<SchoolEmailIncompleteFailure>());
      });

      test('계약에 없는 code(SOCIAL_ONLY · PROFILE_NOT_FOUND)는 서버 문구를 그대로', () async {
        for (final (status, code, message) in [
          (403, 'SCHOOL_EMAIL_SOCIAL_ONLY', '소셜 로그인 계정만 학교 메일을 인증할 수 있어요'),
          (404, 'PROFILE_NOT_FOUND', '프로필을 찾을 수 없어요'),
        ]) {
          respond = (_) => json(status, {'detail': message, 'code': code});

          final failure = failureOf(await buildRepository().complete('temp-token'));

          expect(failure, isA<ServerRejectedFailure>(), reason: code);
          expect(failure!.toDisplayMessage(), message, reason: code);
        }
      });
    });

    // ponytail: 옛 서버(code 없음) 호환 — 서버 배포 뒤 제거 가능.
    group('code 가 없으면(옛 서버) 문구로 가른다', () {
      test('403 "이미 학교 메일 인증이 끝났어요" 는 성공과 같이 본다', () async {
        respond = (_) => json(403, {'detail': '이미 학교 메일 인증이 끝났어요'});

        expect(failureOf(await buildRepository().complete('temp-token')), isNull);
      });

      test('403 "학교 메일 인증이 끝나지 않았어요" 는 SchoolEmailNotConfirmedFailure', () async {
        respond = (_) => json(403, {'detail': '학교 메일 인증이 끝나지 않았어요'});

        expect(failureOf(await buildRepository().complete('temp-token')), isA<SchoolEmailNotConfirmedFailure>());
      });

      test('422 거절 문구(새 문구 · 훅 문구 · 옛 호환 문구)는 SchoolEmailRejectedFailure 에 그대로', () async {
        for (final message in [
          '등록되지 않은 학교 메일이에요',
          '재가입이 제한된 메일이에요',
          '재가입이 제한된 이메일이에요',
          '허용되지 않은 학교 이메일이에요',
        ]) {
          respond = (_) => json(422, {'detail': message});

          final failure = failureOf(await buildRepository().complete('temp-token'));

          expect(failure, isA<SchoolEmailRejectedFailure>(), reason: message);
          expect(failure!.toDisplayMessage(), message, reason: message);
        }
      });

      test('409 provider 는 code 없이도 SchoolEmailTakenFailure', () async {
        respond = (_) => json(409, {'detail': '이 메일은 카카오로 가입돼 있어요', 'provider': 'kakao'});

        final failure = failureOf(await buildRepository().complete('temp-token'));

        expect(failure, isA<SchoolEmailTakenFailure>());
        expect(failure!.toDisplayMessage(), '이 메일은 카카오로 가입돼 있어요');
      });
    });

    test('503 · 네트워크는 "학교 메일 인증을 마치지 못했어요"', () async {
      for (final response in [
        () => json(503, {'detail': '잠시 뒤 다시 시도해 주세요'}),
        () => throw http.ClientException('network'),
      ]) {
        respond = (_) => response();

        final failure = failureOf(await buildRepository().complete('temp-token'));

        expect(failure, isA<SchoolEmailIncompleteFailure>());
        expect(failure!.toDisplayMessage(), '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요');
      }
    });

    // 임시 연결은 성공 · 409 · 422 · 02 로 돌아갈 때 · 로그아웃 · 앱 종료에서만 비운다(지시문 13 A-5).
    group('임시 연결을 비우는 때', () {
      final ends = <String, http.Response Function()>{
        '성공': () => json(200, {'ok': true}),
        '이미 인증': () => json(403, {'detail': '이미 학교 메일 인증이 끝났어요', 'code': 'SCHOOL_EMAIL_ALREADY_VERIFIED'}),
        '409': () => json(409, {'detail': '이 메일은 구글로 가입돼 있어요', 'code': 'SCHOOL_EMAIL_TAKEN', 'provider': 'google'}),
        '422': () => json(422, {'detail': '등록되지 않은 학교 메일이에요', 'code': 'SCHOOL_EMAIL_DOMAIN_NOT_ALLOWED'}),
      };
      for (final MapEntry(key: name, value: response) in ends.entries) {
        test('$name 이면 이 기기에서만 로그아웃해 비운다', () async {
          respond = (_) => response();
          final repository = await openedRepository();

          await repository.complete('temp-token');

          verify(() => temporary.signOut(scope: SignOutScope.local)).called(1);
        });
      }

      final keeps = <String, http.Response Function()>{
        '네트워크': () => throw http.ClientException('network'),
        '503': () => json(503, {'detail': '잠시 뒤 다시 시도해 주세요', 'code': 'AUTH_UNAVAILABLE'}),
        'SCHOOL_EMAIL_NOT_CONFIRMED': () =>
            json(403, {'detail': '학교 메일 인증이 끝나지 않았어요', 'code': 'SCHOOL_EMAIL_NOT_CONFIRMED'}),
      };
      for (final MapEntry(key: name, value: response) in keeps.entries) {
        test('$name 이면 비우지 않는다 — 같은 03 에서 complete 만 다시 부를 수 있게', () async {
          respond = (_) => response();
          final repository = await openedRepository();

          await repository.complete('temp-token');

          verifyNever(() => temporary.signOut(scope: any(named: 'scope')));
        });
      }

      test('02 로 돌아가면(discard) 비운다', () async {
        final repository = await openedRepository();

        await repository.discard();

        verify(() => temporary.signOut(scope: SignOutScope.local)).called(1);
      });
    });
  });
}
