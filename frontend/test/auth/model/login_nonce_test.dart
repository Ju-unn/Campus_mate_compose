import 'dart:math';

import 'package:campus_mate/auth/model/login_nonce.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginNonce', () {
    test('카카오 · 구글에 주는 값은 원본의 SHA-256 소문자 16진 문자열이다', () {
      // "abc" 의 SHA-256 은 FIPS 180-2 부록의 시험 벡터다.
      const nonce = LoginNonce('abc');

      expect(nonce.forProvider(), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('Supabase 에 주는 값은 해시하지 않은 원본이다', () {
      const nonce = LoginNonce('abc');

      expect(nonce.forSupabase(), 'abc');
      expect(nonce.forSupabase(), isNot(nonce.forProvider()));
    });

    test('만들 때마다 다른 원본이 나온다', () {
      final first = LoginNonce.generate();
      final second = LoginNonce.generate();

      expect(first.forSupabase(), isNot(second.forSupabase()));
    });

    test('원본은 32자 이상, URL 에 그대로 실을 수 있는 글자로만 되어 있다', () {
      final nonce = LoginNonce.generate(random: Random(7));

      expect(nonce.forSupabase().length, greaterThanOrEqualTo(32));
      expect(nonce.forSupabase(), matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('해시는 64자 소문자 16진수다', () {
      final hashed = LoginNonce.generate().forProvider();

      expect(hashed, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
