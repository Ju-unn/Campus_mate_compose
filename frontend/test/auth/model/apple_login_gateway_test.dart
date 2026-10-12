import 'package:campus_mate/auth/model/apple_login_gateway.dart';
import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show
        AppleIDAuthorizationScopes,
        AuthorizationErrorCode,
        SignInWithAppleAuthorizationException,
        SignInWithAppleNotSupportedException;

/// 실제 애플 로그인 창 대신 쓰는 가짜. 넘겨받은 nonce 를 적어 둔다.
class _FakeAppleClient implements AppleLoginClient {
  final List<String> nonces = [];
  Object? error;
  String? idToken = 'apple-id-token';

  @override
  Future<String?> requestIdToken(String hashedNonce) async {
    nonces.add(hashedNonce);
    final current = error;
    if (current != null) {
      throw current;
    }
    return idToken;
  }
}

Failure? _failureOf(Result<SocialCredential> result) => result.when(onSuccess: (_) => null, onFailure: (f) => f);

bool _isBoundTo(Result<SocialCredential> result, String hashedNonce) =>
    result.when(onSuccess: (credential) => credential.isBoundTo(hashedNonce), onFailure: (_) => false);

SignInWithAppleAuthorizationException _authorizationError(AuthorizationErrorCode code) =>
    SignInWithAppleAuthorizationException(code: code, message: 'message');

void main() {
  test('애플 로그인 창에는 원본 nonce 의 SHA-256(소문자 16진)을 주고, 받은 ID 토큰을 그 원본과 묶는다', () async {
    final client = _FakeAppleClient();

    final result = await AppleLoginGateway(client).obtainCredential();

    expect(client.nonces.single, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(_isBoundTo(result, client.nonces.single), isTrue);
  });

  test('로그인할 때마다 새 nonce 를 쓴다', () async {
    final client = _FakeAppleClient();
    final gateway = AppleLoginGateway(client);

    await gateway.obtainCredential();
    await gateway.obtainCredential();

    expect(client.nonces.toSet(), hasLength(2));
  });

  test('사용자가 애플 로그인 창을 닫으면(canceled) 취소다', () async {
    final client = _FakeAppleClient()..error = _authorizationError(AuthorizationErrorCode.canceled);

    final result = await AppleLoginGateway(client).obtainCredential();

    expect(_failureOf(result), isA<LoginCancelledFailure>());
  });

  group('취소가 아닌 오류는 실패다', () {
    final errors = <String, Object>{
      'failed': _authorizationError(AuthorizationErrorCode.failed),
      'unknown(Apple ID 미로그인 등)': _authorizationError(AuthorizationErrorCode.unknown),
      'notHandled': _authorizationError(AuthorizationErrorCode.notHandled),
      '지원하지 않는 기기': const SignInWithAppleNotSupportedException(message: 'not supported'),
      '플랫폼 오류': PlatformException(code: 'ERROR'),
    };
    for (final MapEntry(key: name, value: error) in errors.entries) {
      test(name, () async {
        final client = _FakeAppleClient()..error = error;

        final result = await AppleLoginGateway(client).obtainCredential();

        expect(_failureOf(result), isA<SocialLoginFailure>());
      });
    }
  });

  test('identityToken 이 없으면 실패다', () async {
    final client = _FakeAppleClient()..idToken = null;

    final result = await AppleLoginGateway(client).obtainCredential();

    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('identityToken 이 빈 글자여도 실패다', () async {
    final client = _FakeAppleClient()..idToken = '';

    final result = await AppleLoginGateway(client).obtainCredential();

    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('앱 로그아웃 때 할 일이 없어도 던지지 않는다(애플은 앱 안에 로그인 상태를 두지 않는다)', () async {
    final client = _FakeAppleClient();

    await expectLater(AppleLoginGateway(client).signOut(), completes);
    expect(client.nonces, isEmpty);
  });

  group('SdkAppleLoginClient', () {
    test('애플 창에는 이메일만 묻는다(앱이 이름을 읽지도 저장하지도 않아 최소 수집)', () {
      expect(SdkAppleLoginClient.scopes, [AppleIDAuthorizationScopes.email]);
    });
  });
}
