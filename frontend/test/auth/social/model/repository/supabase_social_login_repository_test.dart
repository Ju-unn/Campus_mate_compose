import 'dart:convert';

import 'package:campus_mate/auth/social/model/data/login_nonce.dart';
import 'package:campus_mate/auth/social/model/data/social_provider.dart';
import 'package:campus_mate/auth/social/model/repository/apple_login_gateway.dart';
import 'package:campus_mate/auth/social/model/repository/social_login_repository.dart';
import 'package:campus_mate/auth/social/model/repository/supabase_social_login_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show AuthorizationErrorCode, SignInWithAppleAuthorizationException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_id_token_gateway.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

/// 실제 애플 창 대신 쓰는 가짜. 애플 창에 넘어간(해시한) nonce 를 적어 둔다.
class _FakeAppleClient implements AppleLoginClient {
  final List<String> nonces = [];
  Object? error;

  @override
  Future<String?> requestIdToken(String hashedNonce) async {
    nonces.add(hashedNonce);
    final current = error;
    if (current != null) {
      Error.throwWithStackTrace(current, StackTrace.current);
    }
    return 'apple-id-token';
  }

  @override
  Future<String> requestAuthorizationCode() => throw UnimplementedError('탈퇴용 — 로그인은 부르지 않는다');
}

const _rawNonce = LoginNonce('raw-nonce-value');

Failure? _failureOf(Result<void> result) => result.when(onSuccess: (_) => null, onFailure: (f) => f);

void main() {
  setUpAll(() => registerFallbackValue(OAuthProvider.google));

  late MockGoTrueClient auth;
  late FakeIdTokenGateway kakao;
  late FakeIdTokenGateway google;
  late SupabaseSocialLoginRepository repository;

  void stubSignIn() {
    when(() => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        )).thenAnswer((_) async => AuthResponse());
  }

  setUp(() {
    auth = MockGoTrueClient();
    kakao = FakeIdTokenGateway(const Success(SocialCredential('kakao-id-token', _rawNonce)));
    google = FakeIdTokenGateway(const Success(SocialCredential('google-id-token', _rawNonce)));
    repository = SupabaseSocialLoginRepository(
      auth,
      {SocialProvider.kakao: kakao, SocialProvider.google: google},
    );
  });

  test('카카오 ID 토큰을 Supabase 에 넘길 때 nonce 는 해시가 아니라 원본이다', () async {
    stubSignIn();

    final result = await repository.signIn(SocialProvider.kakao);

    expect(_failureOf(result), isNull);
    verify(() => auth.signInWithIdToken(
          provider: OAuthProvider.kakao,
          idToken: 'kakao-id-token',
          nonce: 'raw-nonce-value',
        )).called(1);
    verifyNever(() => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: _rawNonce.forProvider(),
        ));
  });

  test('구글은 구글 게이트웨이와 OAuthProvider.google 을 쓴다', () async {
    stubSignIn();

    await repository.signIn(SocialProvider.google);

    expect((kakao.calls, google.calls), (0, 1));
    verify(() => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          nonce: 'raw-nonce-value',
        )).called(1);
  });

  test('게이트웨이가 취소면 Supabase 를 부르지 않고 취소를 그대로 돌려준다', () async {
    kakao.result = const FailureResult(LoginCancelledFailure());

    final result = await repository.signIn(SocialProvider.kakao);

    expect(_failureOf(result), isA<LoginCancelledFailure>());
    verifyNever(() => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        ));
  });

  test('Supabase 가 거절하면(AuthException) 실패다', () async {
    when(() => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        )).thenThrow(const AuthException('nonce mismatch', statusCode: '400'));

    final result = await repository.signIn(SocialProvider.kakao);

    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('네트워크 오류 같은 그 밖의 예외도 실패다', () async {
    when(() => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        )).thenThrow(Exception('socket'));

    final result = await repository.signIn(SocialProvider.google);

    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('게이트웨이를 넣지 않은 공급자는 Supabase 를 부르지 않고 실패다', () async {
    // 이 시험의 저장소에는 애플 게이트웨이를 넣지 않았다.
    final result = await repository.signIn(SocialProvider.apple);

    expect(_failureOf(result), isA<SocialLoginFailure>());
    verifyNever(() => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        ));
  });

  group('애플(실제 AppleLoginGateway + 가짜 애플 창)', () {
    late _FakeAppleClient appleClient;
    late SupabaseSocialLoginRepository withApple;

    setUp(() {
      appleClient = _FakeAppleClient();
      withApple = SupabaseSocialLoginRepository(auth, {SocialProvider.apple: AppleLoginGateway(appleClient)});
    });

    test('identityToken 과 원본 nonce 를 OAuthProvider.apple 로 넘기고, 원본의 SHA-256 이 애플 창에 준 값이다', () async {
      stubSignIn();

      final result = await withApple.signIn(SocialProvider.apple);

      expect(_failureOf(result), isNull);
      final rawNonce = verify(() => auth.signInWithIdToken(
            provider: OAuthProvider.apple,
            idToken: 'apple-id-token',
            nonce: captureAny(named: 'nonce'),
          )).captured.single as String;
      final hashedNonce = appleClient.nonces.single;
      expect(rawNonce, isNot(hashedNonce));
      expect(sha256.convert(utf8.encode(rawNonce)).toString(), hashedNonce);
    });

    test('애플 창을 닫으면 Supabase 를 부르지 않고 취소다', () async {
      appleClient.error = const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'canceled',
      );

      final result = await withApple.signIn(SocialProvider.apple);

      expect(_failureOf(result), isA<LoginCancelledFailure>());
      verifyNever(() => auth.signInWithIdToken(
            provider: any(named: 'provider'),
            idToken: any(named: 'idToken'),
            nonce: any(named: 'nonce'),
          ));
    });

    test('Supabase 가 애플 토큰을 거절하면 실패다', () async {
      when(() => auth.signInWithIdToken(
            provider: any(named: 'provider'),
            idToken: any(named: 'idToken'),
            nonce: any(named: 'nonce'),
          )).thenThrow(const AuthException('Unacceptable audience', statusCode: '400'));

      final result = await withApple.signIn(SocialProvider.apple);

      expect(_failureOf(result), isA<SocialLoginFailure>());
    });
  });

  test('앱 로그아웃 때 모든 공급자 게이트웨이의 로그아웃을 부른다', () async {
    await repository.signOutProviders();

    expect((kakao.signOutCalls, google.signOutCalls), (1, 1));
  });

  // 구글 플레이 심사원 전용 아이디 · 비밀번호 로그인(시작 화면 로고 7번 탭). 시험 값은 모두 가짜다.
  group('signInWithPassword(심사원 로그인)', () {
    const email = 'reviewer@example.test';
    const password = 'fake-password-1';

    void stubPasswordSignIn() {
      when(() => auth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => AuthResponse());
    }

    void stubPasswordFailure(Object error) {
      when(() => auth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(error);
    }

    test('이메일 · 비밀번호를 그대로 Supabase signInWithPassword 에 넘긴다', () async {
      stubPasswordSignIn();

      final result = await repository.signInWithPassword(email, password);

      expect(_failureOf(result), isNull);
      verify(() => auth.signInWithPassword(email: email, password: password)).called(1);
    });

    test('소셜 게이트웨이와 signInWithIdToken 은 건드리지 않고, 가입(signUp)은 어떤 경우에도 부르지 않는다', () async {
      stubPasswordSignIn();

      await repository.signInWithPassword(email, password);
      stubPasswordFailure(const AuthException('Invalid login credentials', statusCode: '400', code: 'invalid_credentials'));
      await repository.signInWithPassword(email, password);

      expect((kakao.calls, google.calls), (0, 0));
      verifyNever(() => auth.signInWithIdToken(
            provider: any(named: 'provider'),
            idToken: any(named: 'idToken'),
            nonce: any(named: 'nonce'),
          ));
      verifyNever(() => auth.signUp(email: any(named: 'email'), password: any(named: 'password')));
    });

    test('잘못된 아이디 · 비밀번호(400 invalid_credentials)는 기존 로그인 실패(SocialLoginFailure)다', () async {
      stubPasswordFailure(const AuthException('Invalid login credentials', statusCode: '400', code: 'invalid_credentials'));

      final result = await repository.signInWithPassword(email, password);

      expect(_failureOf(result), isA<SocialLoginFailure>());
    });

    test('한도에 걸리면(429) RateLimitedFailure 다 — 서버 문구 없이 공용 문구를 보인다', () async {
      stubPasswordFailure(const AuthException('Request rate limit reached', statusCode: '429', code: 'over_request_rate_limit'));

      final failure = _failureOf(await repository.signInWithPassword(email, password));

      expect(failure, isA<RateLimitedFailure>());
      expect((failure! as RateLimitedFailure).serverMessage, isNull);
    });

    test('네트워크 오류 같은 그 밖의 예외도 SocialLoginFailure 다', () async {
      stubPasswordFailure(Exception('socket'));

      final result = await repository.signInWithPassword(email, password);

      expect(_failureOf(result), isA<SocialLoginFailure>());
    });

    test('실패 로그에는 오류 종류만 남고 이메일 · 비밀번호는 없다', () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = original);
      stubPasswordFailure(const AuthException('bad $email $password', statusCode: '400'));

      await repository.signInWithPassword(email, password);

      expect(logs, isNotEmpty);
      expect(logs.join(), isNot(contains(password)));
      expect(logs.join(), isNot(contains(email)));
    });
  });
}
