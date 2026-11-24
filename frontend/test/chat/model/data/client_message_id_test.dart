import 'package:campus_mate/chat/model/data/client_message_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uuid v4 표준 모양(8-4-4-4-12 소문자 16진)이다', () {
    final id = newClientMessageId();

    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')));
  });

  test('버전 칸은 4, 변형 칸은 8 · 9 · a · b 중 하나다 — 서버의 UUID 검사를 통과하는 모양', () {
    for (var i = 0; i < 200; i++) {
      final id = newClientMessageId();

      expect(id[14], '4', reason: id);
      expect('89ab', contains(id[19]), reason: id);
    }
  });

  test('부를 때마다 다른 값이다', () {
    expect(newClientMessageId(), isNot(newClientMessageId()));
  });
}
