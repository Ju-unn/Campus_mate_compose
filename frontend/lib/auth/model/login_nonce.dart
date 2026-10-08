import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 소셜 로그인 한 번에 쓰는 일회용 값(ID 토큰 재사용 공격을 막는다).
///
/// **카카오 · 구글에는 원본의 SHA-256(소문자 16진)을, Supabase `signInWithIdToken` 에는 원본을 준다.**
/// 공급자는 받은 값을 ID 토큰의 `nonce` 에 그대로 싣고, Supabase 는 원본을 해시해 그 값과 맞춰 본다.
/// 둘을 뒤바꾸면 Supabase 가 토큰을 거절한다(스파이크에서 안드로이드 실기기로 확인한 규칙).
class LoginNonce {
  const LoginNonce(this._raw);

  /// 무작위 원본을 만든다. 기본은 암호학적으로 안전한 난수다.
  factory LoginNonce.generate({Random? random}) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(_byteLength, (_) => source.nextInt(_byteRange));
    // URL 에 그대로 실을 수 있게 base64url 로, 끝의 '=' 은 뗀다.
    return LoginNonce(base64UrlEncode(bytes).replaceAll('=', ''));
  }

  /// 32바이트 = base64url 43자.
  static const _byteLength = 32;
  static const _byteRange = 256;

  final String _raw;

  /// 카카오 · 구글 SDK 에 넘길 값.
  String forProvider() => sha256.convert(utf8.encode(_raw)).toString();

  /// Supabase `signInWithIdToken(nonce:)` 에 넘길 값.
  String forSupabase() => _raw;
}
