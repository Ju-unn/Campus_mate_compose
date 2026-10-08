import 'package:campus_mate/auth/model/google_login_gateway.dart';
import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInException, GoogleSignInExceptionCode;

/// 실제 GoogleSignIn 대신 쓰는 가짜. initialize 에 받은 nonce 와 호출 횟수를 적어 둔다.
class _FakeGoogleClient implements GoogleLoginClient {
  _FakeGoogleClient({this.configured = true});

  final bool configured;
  final List<String> initializedNonces = [];
  int authenticateCalls = 0;
  Object? initializeError;
  Object? authenticateError;
  String? idToken = 'google-id-token';

  @override
  bool isConfigured() => configured;

  @override
  Future<void> initialize(String hashedNonce) async {
    initializedNonces.add(hashedNonce);
    final error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<String?> authenticate() async {
    authenticateCalls++;
    final error = authenticateError;
    if (error != null) {
      throw error;
    }
    return idToken;
  }
}

Failure? _failureOf(Result<SocialCredential> result) => result.when(onSuccess: (_) => null, onFailure: (f) => f);

bool _isBoundTo(Result<SocialCredential> result, String hashedNonce) =>
    result.when(onSuccess: (credential) => credential.isBoundTo(hashedNonce), onFailure: (_) => false);

void main() {
  test('initialize 에 원본 nonce 의 해시를 주고, 받은 ID 토큰을 그 원본과 묶는다', () async {
    final client = _FakeGoogleClient();

    final result = await GoogleLoginGateway(client).obtainCredential();

    expect(client.initializedNonces.single, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(_isBoundTo(result, client.initializedNonces.single), isTrue);
    expect(client.authenticateCalls, 1);
  });

  test('initialize 는 몇 번 로그인해도 한 번만 부르고(v7 규칙), 그때의 nonce 를 계속 쓴다', () async {
    final client = _FakeGoogleClient()..authenticateError = const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
    final gateway = GoogleLoginGateway(client);

    await gateway.obtainCredential();
    client.authenticateError = null;
    final result = await gateway.obtainCredential();

    expect(client.initializedNonces, hasLength(1));
    expect(client.authenticateCalls, 2);
    expect(_isBoundTo(result, client.initializedNonces.single), isTrue);
  });

  test('계정 고르기를 닫으면(canceled) 취소다', () async {
    final client = _FakeGoogleClient()..authenticateError = const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);

    final result = await GoogleLoginGateway(client).obtainCredential();

    expect(_failureOf(result), isA<LoginCancelledFailure>());
  });

  test('그 밖의 GoogleSignInException 은 실패다', () async {
    final client = _FakeGoogleClient()
      ..authenticateError = const GoogleSignInException(code: GoogleSignInExceptionCode.clientConfigurationError);

    final result = await GoogleLoginGateway(client).obtainCredential();

    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('ID 토큰이 없으면 실패다', () async {
    final client = _FakeGoogleClient()..idToken = null;

    final result = await GoogleLoginGateway(client).obtainCredential();

    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('웹 클라이언트 ID 가 없는 빌드면 SDK 를 부르지 않고 실패다', () async {
    final client = _FakeGoogleClient(configured: false);

    final result = await GoogleLoginGateway(client).obtainCredential();

    expect(client.initializedNonces, isEmpty);
    expect(client.authenticateCalls, 0);
    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('initialize 가 실패하면 실패이고, 다음 로그인 때 다시 initialize 를 시도한다', () async {
    final client = _FakeGoogleClient()..initializeError = StateError('init');
    final gateway = GoogleLoginGateway(client);

    final first = await gateway.obtainCredential();
    client.initializeError = null;
    final second = await gateway.obtainCredential();

    expect(_failureOf(first), isA<SocialLoginFailure>());
    expect(_failureOf(second), isNull);
    expect(client.initializedNonces, hasLength(2));
  });

  group('SdkGoogleLoginClient', () {
    test('웹 클라이언트 ID 가 비어 있으면 설정되지 않은 것으로 본다', () {
      expect(const SdkGoogleLoginClient('').isConfigured(), isFalse);
      expect(const SdkGoogleLoginClient(' ').isConfigured(), isFalse);
      expect(const SdkGoogleLoginClient('client-id').isConfigured(), isTrue);
    });
  });
}
