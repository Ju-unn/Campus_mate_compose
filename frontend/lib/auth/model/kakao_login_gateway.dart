import 'package:campus_mate/auth/model/login_nonce.dart';
import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// 카카오 SDK 에도 `User` 가 있어 gotrue 의 `User` 와 겹친다 — 쓰는 것만 꺼낸다.
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart'
    show AuthErrorCause, ClientErrorCause, KakaoAuthException, KakaoClientException, KakaoSdk, UserApi,
        isKakaoTalkInstalled;

/// 카카오톡이 깔려 있지만 카카오 계정이 연결되지 않았을 때 카카오톡이 돌려주는 오류 종류
/// (`com.kakao.sdk.talk.error.type`). SDK 2.0.1 안드로이드는 이 값을 그대로 `PlatformException.code` 로 올린다
/// (`TalkAuthCodeActivity.handleAuthResult`).
const _talkNotSupportedCode = 'NotSupportError';

/// 사용자가 카카오톡 · 카카오 계정 로그인 창을 닫았을 때 SDK 가 올리는 코드(안드로이드 · iOS 같음).
const _cancelledCode = 'CANCELED';

/// 카카오 SDK 호출만 모은 얇은 층. [KakaoLoginGateway] 의 분기(전환 · 취소)를 SDK 없이 시험하려고 둔다.
/// 각 로그인은 ID 토큰을 돌려준다(없으면 null — 카카오 개발자 콘솔에서 OpenID Connect 를 켜지 않은 경우).
abstract interface class KakaoLoginClient {
  /// 네이티브 앱 키가 들어 있는 빌드인지. 아니면 SDK 를 부르지 않는다.
  bool isConfigured();

  /// 카카오 SDK 가 들고 있는 토큰을 지운다(`UserApi.instance.logout()`).
  Future<void> logout();

  Future<bool> isTalkInstalled();

  Future<String?> loginWithTalk(String hashedNonce);

  Future<String?> loginWithAccount(String hashedNonce);
}

/// 실제 카카오 SDK(`kakao_flutter_sdk_user` 2.0.1)를 부른다.
class SdkKakaoLoginClient implements KakaoLoginClient {
  const SdkKakaoLoginClient(this._nativeAppKey);

  final String _nativeAppKey;

  @override
  bool isConfigured() => _nativeAppKey.trim().isNotEmpty;

  @override
  Future<void> logout() => UserApi.instance.logout();

  @override
  Future<bool> isTalkInstalled() => isKakaoTalkInstalled();

  @override
  Future<String?> loginWithTalk(String hashedNonce) async {
    final token = await UserApi.instance.loginWithKakaoTalk(nonce: hashedNonce);
    return token.idToken;
  }

  @override
  Future<String?> loginWithAccount(String hashedNonce) async {
    final token = await UserApi.instance.loginWithKakaoAccount(nonce: hashedNonce);
    return token.idToken;
  }
}

/// 카카오 로그인으로 ID 토큰을 받아 온다(스파이크에서 안드로이드 실기기로 검증한 흐름).
///
/// 카카오톡이 있으면 카카오톡으로, 없거나 카카오톡에 계정이 연결되지 않았으면(`NotSupportError`)
/// 카카오 계정 로그인으로 **자동 전환**한다. 사용자가 취소한 경우는 전환하지 않는다.
class KakaoLoginGateway implements IdTokenGateway {
  const KakaoLoginGateway(this._client);

  final KakaoLoginClient _client;

  @override
  Future<Result<SocialCredential>> obtainCredential() async {
    if (!_client.isConfigured()) {
      return const FailureResult(SocialLoginFailure());
    }
    // 로그인할 때마다 새 nonce — 카카오는 호출마다 nonce 를 받는다.
    final nonce = LoginNonce.generate();
    try {
      return _toCredential(await _login(nonce.forProvider()), nonce);
    } on Object catch (error) {
      // 키 · 토큰 · 이메일은 남기지 않는다 — 오류 종류 이름만.
      debugPrint('카카오 로그인 실패: ${error.runtimeType}');
      return FailureResult(_isCancel(error) ? const LoginCancelledFailure() : const SocialLoginFailure());
    }
  }

  /// 키가 없는 빌드는 SDK 를 초기화하지 않았으므로 부르지 않는다. 카카오로 로그인한 적이 없어 토큰이 없을 때도
  /// SDK 가 던지는데, 앱 로그아웃은 이미 끝났으므로 삼킨다.
  @override
  Future<void> signOut() async {
    if (!_client.isConfigured()) {
      return;
    }
    try {
      await _client.logout();
    } on Object catch (error) {
      debugPrint('카카오 로그아웃 실패: ${error.runtimeType}');
    }
  }

  Future<String?> _login(String hashedNonce) async {
    if (!await _client.isTalkInstalled()) {
      return _client.loginWithAccount(hashedNonce);
    }
    try {
      return await _client.loginWithTalk(hashedNonce);
    } on PlatformException catch (error) {
      if (error.code != _talkNotSupportedCode) {
        rethrow;
      }
      return _client.loginWithAccount(hashedNonce);
    }
  }

  Result<SocialCredential> _toCredential(String? idToken, LoginNonce nonce) {
    if (idToken == null || idToken.isEmpty) {
      return const FailureResult(SocialLoginFailure());
    }
    return Success(SocialCredential(idToken, nonce));
  }

  /// SDK 2.0.1 소스에서 확인한 취소 세 갈래 — 창 닫기(`CANCELED`), 선택 시트 닫기(`cancelled`),
  /// 동의 화면에서 취소(`access_denied`, 카카오 계정 로그인의 리다이렉트 오류).
  static bool _isCancel(Object error) {
    return switch (error) {
      PlatformException(code: _cancelledCode) => true,
      KakaoClientException(reason: ClientErrorCause.cancelled) => true,
      KakaoAuthException(error: AuthErrorCause.accessDenied) => true,
      _ => false,
    };
  }
}

/// `main()` 에서 한 번 부른다. 키가 없는 빌드(시험 · CI)는 초기화를 건너뛰어 앱이 그대로 켜지고,
/// 카카오 버튼은 [SdkKakaoLoginClient.isConfigured] 가 막아 실패 토스트가 뜬다.
Future<void> initializeKakaoSdk(String nativeAppKey, {Future<void> Function(String key)? init}) async {
  if (nativeAppKey.trim().isEmpty) {
    return;
  }
  await (init ?? _initializeSdk)(nativeAppKey);
}

Future<void> _initializeSdk(String nativeAppKey) => KakaoSdk.init(nativeAppKey: nativeAppKey);
