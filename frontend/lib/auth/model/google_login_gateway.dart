import 'package:campus_mate/auth/model/login_nonce.dart';
import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// `GoogleSignIn.instance` 호출만 모은 얇은 층. [GoogleLoginGateway] 의 분기를 SDK 없이 시험하려고 둔다.
abstract interface class GoogleLoginClient {
  /// 웹 클라이언트 ID 가 들어 있는 빌드인지. 아니면 SDK 를 부르지 않는다.
  bool isConfigured();

  /// v7 규칙: 앱이 살아 있는 동안 **한 번만** 부른다. nonce 는 여기서만 받는다(7.2.0 에 호출마다 바꾸는 API 가 없다).
  Future<void> initialize(String hashedNonce);

  /// 계정을 고르게 하고 ID 토큰을 돌려준다(없으면 null).
  Future<String?> authenticate();
}

/// 실제 `google_sign_in` 7.2.0 을 부른다.
class SdkGoogleLoginClient implements GoogleLoginClient {
  const SdkGoogleLoginClient(this._webClientId);

  /// Supabase 가 ID 토큰의 aud 로 확인하는 **웹** 클라이언트 ID(`serverClientId`).
  final String _webClientId;

  @override
  bool isConfigured() => _webClientId.trim().isNotEmpty;

  @override
  Future<void> initialize(String hashedNonce) {
    return GoogleSignIn.instance.initialize(serverClientId: _webClientId, nonce: hashedNonce);
  }

  @override
  Future<String?> authenticate() async {
    final account = await GoogleSignIn.instance.authenticate(scopeHint: const ['email']);
    return account.authentication.idToken;
  }
}

/// 구글 로그인으로 ID 토큰을 받아 온다.
///
/// `google_sign_in` 7.2.0 은 nonce 를 `initialize` 에서만 받고 `initialize` 는 한 번만 불러야 한다.
/// 그래서 원본 nonce 를 첫 로그인 때 하나 만들어 **이 게이트웨이가 살아 있는 동안**(= 앱 프로세스 동안,
/// provider 파일 주석 참고) 계속 쓴다. 스파이크에서 같은 nonce 를 다시 써도 Supabase 가 받는 것을 확인했다.
class GoogleLoginGateway implements IdTokenGateway {
  GoogleLoginGateway(this._client);

  final GoogleLoginClient _client;

  /// 첫 initialize 의 결과 — 그때 만든 원본 nonce. 실패하면 비워 두어 다음 로그인 때 다시 시도한다.
  Future<LoginNonce>? _initialization;

  @override
  Future<Result<SocialCredential>> obtainCredential() async {
    if (!_client.isConfigured()) {
      return const FailureResult(SocialLoginFailure());
    }
    try {
      final nonce = await _initializeOnce();
      return _toCredential(await _client.authenticate(), nonce);
    } on Object catch (error) {
      // 키 · 토큰 · 이메일은 남기지 않는다 — 오류 종류 이름만.
      debugPrint('구글 로그인 실패: ${error.runtimeType}');
      return FailureResult(_isCancel(error) ? const LoginCancelledFailure() : const SocialLoginFailure());
    }
  }

  Future<LoginNonce> _initializeOnce() {
    return _initialization ??= _initialize().catchError((Object error) {
      _initialization = null;
      throw error;
    });
  }

  Future<LoginNonce> _initialize() async {
    final nonce = LoginNonce.generate();
    await _client.initialize(nonce.forProvider());
    return nonce;
  }

  Result<SocialCredential> _toCredential(String? idToken, LoginNonce nonce) {
    if (idToken == null || idToken.isEmpty) {
      return const FailureResult(SocialLoginFailure());
    }
    return Success(SocialCredential(idToken, nonce));
  }

  static bool _isCancel(Object error) {
    return error is GoogleSignInException && error.code == GoogleSignInExceptionCode.canceled;
  }
}
