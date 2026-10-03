import 'package:campus_mate/chat/model/message_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime 채널 상태 → 받는 쪽 신호(결함 A12). 끊기면 Realtime 은 channelError 를 주고 스스로 다시 붙어
/// `subscribed` 를 한 번 더 준다 — 그 두 번째부터가 "다시 붙음" 이다.
void main() {
  late List<Object> errors;
  late int rejoins;
  late void Function(RealtimeSubscribeStatus, Object?) listener;

  setUp(() {
    errors = [];
    rejoins = 0;
    listener = channelStatusListener(onError: errors.add, onRejoined: () => rejoins++);
  });

  test('처음 붙을 때는 다시 붙음이 아니다 — 부르면 다시 구독이 끝없이 돈다', () {
    listener(RealtimeSubscribeStatus.subscribed, null);

    expect(rejoins, 0);
    expect(errors, isEmpty);
  });

  test('끊겼다가 다시 붙으면 오류 한 번 뒤 다시 붙음 한 번', () {
    listener(RealtimeSubscribeStatus.subscribed, null);
    listener(RealtimeSubscribeStatus.channelError, null);
    listener(RealtimeSubscribeStatus.subscribed, null);

    expect(errors, hasLength(1));
    expect(rejoins, 1);
  });

  test('처음 붙기 전에 끊겼다가(타임아웃 · 소켓 연결 실패) 붙어도 다시 붙음이다 — 그 사이 온 줄을 놓친다', () {
    listener(RealtimeSubscribeStatus.timedOut, null);
    listener(RealtimeSubscribeStatus.subscribed, null);

    expect(errors, hasLength(1));
    expect(rejoins, 1);
  });

  test('다시 붙은 뒤 또 붙음이 와도 끊김이 없었으면 한 번뿐이다', () {
    listener(RealtimeSubscribeStatus.channelError, null);
    listener(RealtimeSubscribeStatus.subscribed, null);
    listener(RealtimeSubscribeStatus.subscribed, null);

    expect(rejoins, 1);
  });

  test('타임아웃도 끊김으로 올리고, 우리가 닫은 closed 는 올리지 않는다', () {
    listener(RealtimeSubscribeStatus.timedOut, null);
    listener(RealtimeSubscribeStatus.closed, null);

    expect(errors, hasLength(1));
    expect(rejoins, 0);
  });
}
