import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/auth/school_email/model/data/university_email.dart';
import 'package:campus_mate/auth/school_email/model/data/verification_code.dart';
import 'package:campus_mate/auth/school_email/model/repository/supabase_school_email_repository.dart';
import 'package:campus_mate/auth/school_email/model/repository/temporary_auth_connection.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
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
      main,
    );
  }

  /// 메인(소셜) 연결에 [email] 을 가진 사용자로 로그인해 둔다. 카카오는 메일 없이도 로그인된다(null).
  void signedInAs(String? email, {String? provider}) {
    when(() => main.currentUser).thenReturn(
      User(
        id: 'main-user',
        appMetadata: {'provider': ?provider},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '',
        email: email,
      ),
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
      expect(failureText(AppLocalizationsKo(), failure!), '등록되지 않은 학교 메일이에요');
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

    // 학교 구글 계정으로 로그인해 로그인 메일이 곧 학교 메일이어도 보낸다 — GoTrue 가 그 계정으로 OTP 로그인시키고
    // 서버가 OTP 를 메일 주인 증거로 받아 인증한다(서버 6-f, 2026-11-23). 예전엔 보내기 전에 막아 인증할 길이 없었다.
    group('로그인한 소셜 계정의 메일과 상관없이 보낸다', () {
      setUp(() {
        when(
          () => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')),
        ).thenAnswer((_) async {});
      });

      test('로그인 메일과 같아도(대소문자 · 앞뒤 공백 무시) 그대로 보낸다', () async {
        signedInAs(' Hong@SNU.ac.kr ');

        expect(failureOf(await buildRepository().requestCode(email)), isNull);
        verify(() => temporary.signInWithOtp(email: 'hong@snu.ac.kr', shouldCreateUser: true)).called(1);
      });

      test('다르면 그대로 보낸다', () async {
        signedInAs('hong@gmail.com');

        expect(failureOf(await buildRepository().requestCode(email)), isNull);
        verify(() => temporary.signInWithOtp(email: 'hong@snu.ac.kr', shouldCreateUser: true)).called(1);
      });

      test('로그인 계정에 메일이 없으면(카카오 일부) 그대로 보낸다', () async {
        signedInAs(null);

        expect(failureOf(await buildRepository().requestCode(email)), isNull);
        verify(() => temporary.signInWithOtp(email: 'hong@snu.ac.kr', shouldCreateUser: true)).called(1);
      });
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

    // 시간 초과 뒤 verifyOTP 가 늦게 성공하면 임시 연결에 세션이 남는다. 같은 코드로 다시 확인하면 이미 쓴 코드라
    // "코드가 맞지 않아요" 가 됐다 — 같은 메일의 세션이 있으면 그것을 쓴다.
    group('임시 연결에 이미 세션이 있으면(늦게 성공한 확인)', () {
      void temporaryHasSessionFor(String? sessionEmail) {
        final session = MockSession();
        when(() => session.accessToken).thenReturn('late-token');
        when(() => session.user).thenReturn(
          User(id: 'temp-user', appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: '', email: sessionEmail),
        );
        when(() => temporary.currentSession).thenReturn(session);
      }

      test('같은 메일(대소문자 · 앞뒤 공백 무시)의 세션이면 verifyOTP 를 부르지 않고 그 토큰을 돌려준다', () async {
        temporaryHasSessionFor(' Hong@SNU.ac.kr ');

        final result = await buildRepository().verifyCode(email, code);

        expect(result.when(onSuccess: (token) => token, onFailure: (_) => null), 'late-token');
        verifyNever(
          () => temporary.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: any(named: 'type')),
        );
      });

      test('다른 메일의 세션이면 지금처럼 verifyOTP 로 확인한다', () async {
        temporaryHasSessionFor('other@snu.ac.kr');
        final fresh = MockSession();
        when(() => fresh.accessToken).thenReturn('temp-token');
        verifyAnswers(fresh);

        final result = await buildRepository().verifyCode(email, code);

        expect(result.when(onSuccess: (token) => token, onFailure: (_) => null), 'temp-token');
        verify(() => temporary.verifyOTP(email: 'hong@snu.ac.kr', token: '123456', type: OtpType.email)).called(1);
      });

      // "다시 받기" 로 새 코드가 나갔으면 남은 세션은 옛 코드의 것이다 — 비워야 새 코드를 서버가 확인한다
      // (남겨 두면 아무 6자리나 통과하고, 30분이 지난 세션은 서버가 거절해 다시 받기로도 못 푼다).
      test('새 코드를 보내는 데 성공하면 남은 세션을 비워 다음 확인은 verifyOTP 로 한다', () async {
        temporaryHasSessionFor('hong@snu.ac.kr');
        // gotrue 의 로그아웃처럼 메모리 세션을 지운다.
        when(() => temporary.signOut(scope: any(named: 'scope'))).thenAnswer((_) async {
          when(() => temporary.currentSession).thenReturn(null);
        });
        when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
            .thenAnswer((_) async {});
        final fresh = MockSession();
        when(() => fresh.accessToken).thenReturn('temp-token');
        verifyAnswers(fresh);
        final repository = buildRepository();

        await repository.requestCode(email);
        final result = await repository.verifyCode(email, code);

        expect(result.when(onSuccess: (token) => token, onFailure: (_) => null), 'temp-token');
        verify(() => temporary.verifyOTP(email: 'hong@snu.ac.kr', token: '123456', type: OtpType.email)).called(1);
      });

      test('새 코드 보내기가 실패하면 세션을 남겨 다음 확인은 그 세션을 쓴다', () async {
        temporaryHasSessionFor('hong@snu.ac.kr');
        when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
            .thenThrow(const AuthException('email rate limit', statusCode: '429'));
        final repository = buildRepository();

        await repository.requestCode(email);
        final result = await repository.verifyCode(email, code);

        expect(result.when(onSuccess: (token) => token, onFailure: (_) => null), 'late-token');
        verifyNever(() => temporary.signOut(scope: any(named: 'scope')));
        verifyNever(
          () => temporary.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: any(named: 'type')),
        );
      });
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
        expect(failureText(AppLocalizationsKo(), failure!), '학교 메일 인증을 마치지 못했어요. 잠시 후 다시 시도해 주세요');
      });

      // ALIAS_NOT_ALLOWED: 학교 메일 `+` 별칭 거절(서버 fix/api-security-hardening, 422 SCHOOL_EMAIL_ALIAS).
      test('DOMAIN_NOT_ALLOWED · REJOIN_BLOCKED · ALIAS_NOT_ALLOWED 는 서버 문구를 그대로 담은 SchoolEmailRejectedFailure', () async {
        for (final (code, message) in [
          ('SCHOOL_EMAIL_DOMAIN_NOT_ALLOWED', '등록되지 않은 학교 메일이에요'),
          ('SCHOOL_EMAIL_REJOIN_BLOCKED', '재가입이 제한된 메일이에요'),
          ('SCHOOL_EMAIL_ALIAS_NOT_ALLOWED', '학교 메일 원래 주소로 인증해 주세요'),
        ]) {
          respond = (_) => json(422, {'detail': message, 'code': code});

          final failure = failureOf(await buildRepository().complete('temp-token'));

          expect(failure, isA<SchoolEmailRejectedFailure>(), reason: code);
          expect(failureText(AppLocalizationsKo(), failure!), message, reason: code);
        }
      });

      // 내 소셜은 메인 연결(`appMetadata['provider']`, account_repository 와 같은 방식)에서 읽어 덧붙인다 — 서버는 그대로.
      test('SCHOOL_EMAIL_TAKEN + provider 는 내 소셜(구글)과 견준 SchoolEmailTakenFailure — 다른 소셜이면 그 소셜로 다시 로그인', () async {
        signedInAs(null, provider: 'google');
        respond = (_) => json(409, {'detail': '이 메일은 카카오로 가입돼 있어요', 'code': 'SCHOOL_EMAIL_TAKEN', 'provider': 'kakao'});

        final failure = failureOf(await buildRepository().complete('temp-token'));

        expect(failure, isA<SchoolEmailTakenFailure>());
        expect(takenHintText(AppLocalizationsKo(), failure! as SchoolEmailTakenFailure), '카카오로 로그인해 주세요');
        expect(AppLocalizationsKo().authSchoolEmailRelogin(provider: (failure as SchoolEmailTakenFailure).otherSocialProvider()!), '카카오로 다시 로그인');
      });

      test('쥔 소셜이 내 소셜과 같으면(카카오 = 카카오) 빌려 쓰기 문구, 다시 로그인 없음', () async {
        signedInAs(null, provider: 'kakao');
        respond = (_) => json(409, {'detail': '이 메일은 카카오로 가입돼 있어요', 'code': 'SCHOOL_EMAIL_TAKEN', 'provider': 'kakao'});

        final failure = failureOf(await buildRepository().complete('temp-token'))! as SchoolEmailTakenFailure;

        expect(failureText(AppLocalizationsKo(), failure), '이미 가입된 학교 메일이에요');
        expect(failure.otherSocialProvider(), isNull); // 다시 로그인 단추는 다른 소셜이 쥔 메일에만
      });

      test('AUTH_UNAVAILABLE(503) 는 다시 하라는 문구', () async {
        respond = (_) => json(503, {'detail': '잠시 후 다시 시도해 주세요', 'code': 'AUTH_UNAVAILABLE'});

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
          expect(failureText(AppLocalizationsKo(), failure!), message, reason: code);
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
          expect(failureText(AppLocalizationsKo(), failure!), message, reason: message);
        }
      });

      test('409 provider 는 code 없이도 SchoolEmailTakenFailure', () async {
        signedInAs(null, provider: 'google');
        respond = (_) => json(409, {'detail': '이 메일은 카카오로 가입돼 있어요', 'provider': 'kakao'});

        final failure = failureOf(await buildRepository().complete('temp-token'));

        expect(failure, isA<SchoolEmailTakenFailure>());
        expect(failureText(AppLocalizationsKo(), failure!), '이미 카카오로 가입된 학교 메일이에요');
      });
    });

    test('503 · 네트워크는 "학교 메일 인증을 마치지 못했어요"', () async {
      for (final response in [
        () => json(503, {'detail': '잠시 후 다시 시도해 주세요'}),
        () => throw http.ClientException('network'),
      ]) {
        respond = (_) => response();

        final failure = failureOf(await buildRepository().complete('temp-token'));

        expect(failure, isA<SchoolEmailIncompleteFailure>());
        expect(failureText(AppLocalizationsKo(), failure!), '학교 메일 인증을 마치지 못했어요. 잠시 후 다시 시도해 주세요');
      }
    });

    // 임시 연결은 성공 · 409 · 422 · 02 로 돌아갈 때 · 로그아웃 · 앱 종료에서만 비운다(지시문 13 A-5).
    group('임시 연결을 비우는 때', () {
      final ends = <String, http.Response Function()>{
        '성공': () => json(200, {'ok': true}),
        '이미 인증': () => json(403, {'detail': '이미 학교 메일 인증이 끝났어요', 'code': 'SCHOOL_EMAIL_ALREADY_VERIFIED'}),
        '409': () => json(409, {'detail': '이 메일은 구글로 가입돼 있어요', 'code': 'SCHOOL_EMAIL_TAKEN', 'provider': 'google'}),
        '422': () => json(422, {'detail': '등록되지 않은 학교 메일이에요', 'code': 'SCHOOL_EMAIL_DOMAIN_NOT_ALLOWED'}),
        '422 별칭': () => json(422, {'detail': '학교 메일 원래 주소로 인증해 주세요', 'code': 'SCHOOL_EMAIL_ALIAS_NOT_ALLOWED'}),
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
        '503': () => json(503, {'detail': '잠시 후 다시 시도해 주세요', 'code': 'AUTH_UNAVAILABLE'}),
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

  // 망이 끊겨 GoTrue 응답이 끝내 오지 않아도 버튼이 "진행 중" 에 묶이지 않게 앱 쓰기 상한(writeTimeout)에서 끊는다.
  // testWidgets 의 가짜 시계로 상한을 건너뛴다(fake_async 를 따로 들이지 않는다).
  group('응답이 끝내 오지 않으면 쓰기 상한에서 끊는다', () {
    /// [call] 을 시작해 상한 1초 전에는 아직 기다리고, 상한을 넘기면 끝났는지 본다. 끝난 값을 돌려준다.
    Future<T?> settleAfterTimeout<T>(WidgetTester tester, Future<T> Function() call) async {
      T? value;
      var finished = false;
      unawaited(call().then((result) {
        value = result;
        finished = true;
      }));
      await tester.pump(writeTimeout - const Duration(seconds: 1));
      expect(finished, isFalse, reason: '상한 전에는 기다린다');
      await tester.pump(const Duration(seconds: 2));
      expect(finished, isTrue, reason: '상한을 넘기면 끝난다');
      return value;
    }

    void otpHangs() {
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenAnswer((_) => Completer<void>().future);
    }

    void signOutHangs() {
      when(() => temporary.signOut(scope: any(named: 'scope'))).thenAnswer((_) => Completer<void>().future);
    }

    testWidgets('인증번호 보내기(signInWithOtp)가 안 끝나면 "인증번호를 보내지 못했어요"', (tester) async {
      otpHangs();

      final result = await settleAfterTimeout(tester, () => buildRepository().requestCode(email));

      expect(failureOf(result!), isA<CodeNotSentFailure>());
    });

    testWidgets('코드 확인(verifyOTP)이 안 끝나면 "학교 메일 인증을 마치지 못했어요"', (tester) async {
      when(
        () => temporary.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
      ).thenAnswer((_) => Completer<AuthResponse>().future);

      final result = await settleAfterTimeout(tester, () => buildRepository().verifyCode(email, code));

      expect(failureOf(result!), isA<SchoolEmailIncompleteFailure>());
    });

    testWidgets('인증을 마친 뒤 임시 연결 로그아웃 알림이 안 끝나도 성공으로 끝난다', (tester) async {
      final repository = buildRepository();
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenAnswer((_) async {});
      await repository.requestCode(email);
      signOutHangs();

      final result = await settleAfterTimeout(tester, () => repository.complete('temp-token'));

      expect(failureOf(result!), isNull);
    });

    testWidgets('02 로 돌아갈 때(discard) 로그아웃 알림이 안 끝나도 돌아간다', (tester) async {
      final repository = buildRepository();
      when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
          .thenAnswer((_) async {});
      await repository.requestCode(email);
      signOutHangs();

      await settleAfterTimeout(tester, () async {
        await repository.discard();
        return true;
      });
    });
  });
}
