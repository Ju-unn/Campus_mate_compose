import 'package:campus_mate/auth/model/kakao_login_gateway.dart';
import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart'
    show AuthErrorCause, ClientErrorCause, KakaoAuthException, KakaoClientException;

/// 실제 카카오 SDK 대신 쓰는 가짜. 호출 순서와 넘겨받은 nonce 를 적어 둔다.
class _FakeKakaoClient implements KakaoLoginClient {
  _FakeKakaoClient({this.configured = true, this.talkInstalled = true});

  final bool configured;
  final bool talkInstalled;
  Object? talkError;
  Object? accountError;
  String? idToken = 'kakao-id-token';
  final List<String> calls = [];
  final List<String> nonces = [];

  @override
  bool isConfigured() => configured;

  @override
  Future<bool> isTalkInstalled() async {
    calls.add('installed');
    return talkInstalled;
  }

  @override
  Future<String?> loginWithTalk(String hashedNonce) async {
    calls.add('talk');
    nonces.add(hashedNonce);
    final error = talkError;
    if (error != null) {
      throw error;
    }
    return idToken;
  }

  @override
  Future<String?> loginWithAccount(String hashedNonce) async {
    calls.add('account');
    nonces.add(hashedNonce);
    final error = accountError;
    if (error != null) {
      throw error;
    }
    return idToken;
  }
}

Failure? _failureOf(Result<SocialCredential> result) => result.when(onSuccess: (_) => null, onFailure: (f) => f);

/// 성공 결과의 원본 nonce 가 SDK 에 준 해시와 짝인지. Supabase 에 원본이 가는지는 저장소 시험이 본다.
bool _isBoundTo(Result<SocialCredential> result, String hashedNonce) =>
    result.when(onSuccess: (credential) => credential.isBoundTo(hashedNonce), onFailure: (_) => false);

void main() {
  test('카카오톡이 있으면 카카오톡으로 로그인하고, SDK 에는 원본 nonce 의 해시를 준다', () async {
    final client = _FakeKakaoClient();

    final result = await KakaoLoginGateway(client).obtainCredential();

    expect(client.calls, ['installed', 'talk']);
    expect(client.nonces.single, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(_isBoundTo(result, client.nonces.single), isTrue);
  });

  test('카카오톡이 없으면 카카오 계정으로 로그인한다', () async {
    final client = _FakeKakaoClient(talkInstalled: false);

    final result = await KakaoLoginGateway(client).obtainCredential();

    expect(client.calls, ['installed', 'account']);
    expect(_failureOf(result), isNull);
  });

  test('카카오톡에 카카오 계정이 연결되지 않았으면(NotSupportError) 카카오 계정 로그인으로 자동 전환한다', () async {
    final client = _FakeKakaoClient()..talkError = PlatformException(code: 'NotSupportError');

    final result = await KakaoLoginGateway(client).obtainCredential();

    expect(client.calls, ['installed', 'talk', 'account']);
    expect(_failureOf(result), isNull);
    // 전환해도 같은 nonce 의 해시를 쓴다 — 결과의 원본과 맞아야 Supabase 가 받는다.
    expect(client.nonces.toSet(), hasLength(1));
    expect(_isBoundTo(result, client.nonces.first), isTrue);
  });

  group('사용자가 취소하면 계정 로그인으로 넘어가지 않고 취소로 끝난다', () {
    final cancels = <String, Object>{
      'PlatformException CANCELED': PlatformException(code: 'CANCELED'),
      'KakaoClientException cancelled': KakaoClientException(ClientErrorCause.cancelled, 'User Cancelled'),
      'KakaoAuthException access_denied': KakaoAuthException(AuthErrorCause.accessDenied, 'User denied access'),
    };
    for (final MapEntry(key: name, value: error) in cancels.entries) {
      test(name, () async {
        final client = _FakeKakaoClient()..talkError = error;

        final result = await KakaoLoginGateway(client).obtainCredential();

        expect(client.calls, ['installed', 'talk']);
        expect(_failureOf(result), isA<LoginCancelledFailure>());
      });
    }
  });

  test('카카오 계정 로그인 창을 닫아도 취소다', () async {
    final client = _FakeKakaoClient(talkInstalled: false)..accountError = PlatformException(code: 'CANCELED');

    final result = await KakaoLoginGateway(client).obtainCredential();

    expect(_failureOf(result), isA<LoginCancelledFailure>());
  });

  test('카카오톡 로그인이 다른 이유로 실패하면 전환하지 않고 실패다', () async {
    final client = _FakeKakaoClient()..talkError = PlatformException(code: 'ERROR');

    final result = await KakaoLoginGateway(client).obtainCredential();

    expect(client.calls, ['installed', 'talk']);
    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('ID 토큰이 없으면(OpenID Connect 미설정) 실패다', () async {
    final client = _FakeKakaoClient()..idToken = null;

    final result = await KakaoLoginGateway(client).obtainCredential();

    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('앱 키가 없는 빌드면 SDK 를 부르지 않고 실패다', () async {
    final client = _FakeKakaoClient(configured: false);

    final result = await KakaoLoginGateway(client).obtainCredential();

    expect(client.calls, isEmpty);
    expect(_failureOf(result), isA<SocialLoginFailure>());
  });

  test('로그인할 때마다 새 nonce 를 쓴다', () async {
    final client = _FakeKakaoClient();
    final gateway = KakaoLoginGateway(client);

    await gateway.obtainCredential();
    await gateway.obtainCredential();

    expect(client.nonces.toSet(), hasLength(2));
  });

  group('SdkKakaoLoginClient', () {
    test('앱 키가 비어 있으면 설정되지 않은 것으로 본다', () {
      expect(const SdkKakaoLoginClient('').isConfigured(), isFalse);
      expect(const SdkKakaoLoginClient('  ').isConfigured(), isFalse);
      expect(const SdkKakaoLoginClient('key').isConfigured(), isTrue);
    });
  });

  group('initializeKakaoSdk', () {
    test('앱 키가 비어 있으면 KakaoSdk.init 을 건너뛴다(키 없는 시험 · CI 빌드도 켜진다)', () async {
      final initialized = <String>[];

      await initializeKakaoSdk('', init: (key) async => initialized.add(key));

      expect(initialized, isEmpty);
    });

    test('앱 키가 있으면 그 키로 한 번 초기화한다', () async {
      final initialized = <String>[];

      await initializeKakaoSdk('native-key', init: (key) async => initialized.add(key));

      expect(initialized, ['native-key']);
    });
  });
}
