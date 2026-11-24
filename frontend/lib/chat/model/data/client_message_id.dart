import 'dart:math';

final Random _random = Random.secure();

/// 채팅 한 줄을 보낼 때 싣는 client id — uuid v4 소문자 문자열(8-4-4-4-12).
///
/// 응답을 못 받아 다시 보낸 같은 글을 서버가 이 값으로 알아보고 처음 줄을 돌려준다(1.0.7 #8).
/// uuid 패키지가 직접 의존성이 아니라 `Random.secure()` 로 16바이트를 뽑아 버전 · 변형 비트만 맞춘다(RFC 4122 §4.4).
String newClientMessageId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // 버전 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // 변형 10xx
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
