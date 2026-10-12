import 'package:campus_mate/auth/model/login_nonce.dart';
import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// `SignInWithApple` 호출만 모은 얇은 층. [AppleLoginGateway] 의 분기(취소 · 실패)를 SDK 없이 시험하려고 둔다.
abstract interface class AppleLoginClient {
  /// iOS 애플 로그인 창을 띄우고 identityToken 을 돌려준다(없으면 null).
  Future<String?> requestIdToken(String hashedNonce);
}

/// 실제 `sign_in_with_apple` 8.2.0 을 부른다(iOS 시스템 창). 시작 화면이 iOS 에서만 버튼을 그리므로 안드로이드에서는 불리지 않는다.
class SdkAppleLoginClient implements AppleLoginClient {
  const SdkAppleLoginClient();

  /// 이메일만 묻는다 — 이름(fullName)은 앱이 읽지도 저장하지도 않아 빼서 최소로 모은다(2026-10-13 대장 결정).
  /// 이메일은 비어 있거나 애플 릴레이 주소(privaterelay.appleid.com)일 수 있는데, 앱 · 서버는 소셜 로그인 이메일을
  /// 쓰지 않는다(학교 메일은 별도 인증).
  @visibleForTesting
  static const List<AppleIDAuthorizationScopes> scopes = [AppleIDAuthorizationScopes.email];

  @override
  Future<String?> requestIdToken(String hashedNonce) async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: scopes,
      nonce: hashedNonce,
    );
    return credential.identityToken;
  }
}

/// 애플 로그인으로 ID 토큰을 받아 온다. 카카오처럼 로그인할 때마다 새 nonce 를 만든다 —
/// 애플 창에는 해시를, Supabase 에는 원본을 준다([LoginNonce]).
class AppleLoginGateway implements IdTokenGateway {
  const AppleLoginGateway(this._client);

  final AppleLoginClient _client;

  @override
  Future<Result<SocialCredential>> obtainCredential() async {
    final nonce = LoginNonce.generate();
    try {
      return _toCredential(await _client.requestIdToken(nonce.forProvider()), nonce);
    } on Object catch (error) {
      // 토큰 · 이메일은 남기지 않는다 — 오류 종류 이름만.
      debugPrint('애플 로그인 실패: ${error.runtimeType}');
      return FailureResult(_isCancel(error) ? const LoginCancelledFailure() : const SocialLoginFailure());
    }
  }

  /// 애플 SDK 는 앱 안에 로그인 상태를 두지 않는다(매번 시스템 창이 묻는다) — 지울 것이 없다.
  @override
  Future<void> signOut() async {}

  Result<SocialCredential> _toCredential(String? idToken, LoginNonce nonce) {
    if (idToken == null || idToken.isEmpty) {
      return const FailureResult(SocialLoginFailure());
    }
    return Success(SocialCredential(idToken, nonce));
  }

  /// 애플 로그인 창을 닫으면 `ASAuthorizationError.canceled` → `AuthorizationErrorCode.canceled`.
  static bool _isCancel(Object error) {
    return error is SignInWithAppleAuthorizationException && error.code == AuthorizationErrorCode.canceled;
  }
}
