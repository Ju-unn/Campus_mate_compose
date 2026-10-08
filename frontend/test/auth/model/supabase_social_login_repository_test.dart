import 'package:campus_mate/auth/model/login_nonce.dart';
import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/model/supabase_social_login_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_id_token_gateway.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

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

  test('게이트웨이가 없는 공급자(애플, 이번 PR 미구현)는 실패다', () async {
    final result = await repository.signIn(SocialProvider.apple);

    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('앱 로그아웃 때 모든 공급자 게이트웨이의 로그아웃을 부른다', () async {
    await repository.signOutProviders();

    expect((kakao.signOutCalls, google.signOutCalls), (1, 1));
  });
}
