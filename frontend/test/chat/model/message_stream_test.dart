import 'package:campus_mate/chat/model/message_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime 채널 상태 → 받는 쪽 신호(결함 A12). 끊기면 Realtime 은 channelError 를 주고 스스로 다시 붙어
/// `subscribed` 를 한 번 더 준다 — 그 두 번째부터가 "다시 붙음" 이다.
void main() {
  late List<Object> errors;
  late int rejoins;
  late int readies;
  late void Function(RealtimeSubscribeStatus, Object?) listener;

  setUp(() {
    errors = [];
    rejoins = 0;
    readies = 0;
    listener = channelStatusListener(
      onError: errors.add,
      onRejoined: () => rejoins++,
      onReady: () => readies++,
    );
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

  // 서버는 postgres_changes 복제를 join 성공 **뒤에** 비동기로 만든다 — 처음 붙은 순간부터 복제가 살기 전까지
  // 들어온 줄은 구독도 첫 페이지 읽기도 못 받는다(E-CHAT-67). 그래서 처음 붙음에 "준비됨" 을 알려 한 번 더 읽게 한다.
  test('끊김 없이 처음 붙으면 준비됨이다 — 다시 붙음은 아니다', () {
    listener(RealtimeSubscribeStatus.subscribed, null);

    expect(readies, 1);
    expect(rejoins, 0);
  });

  test('끊겼다가 다시 붙으면 다시 붙음만 부른다 — 준비됨까지 부르면 전체를 두 번 읽는다', () {
    listener(RealtimeSubscribeStatus.subscribed, null);
    listener(RealtimeSubscribeStatus.channelError, null);
    listener(RealtimeSubscribeStatus.subscribed, null);

    expect(rejoins, 1);
    expect(readies, 1); // 처음 붙음 몫뿐
  });

  test('처음 붙기 전에 끊겼다 붙으면 다시 붙음이다 — 준비됨은 아니다', () {
    listener(RealtimeSubscribeStatus.timedOut, null);
    listener(RealtimeSubscribeStatus.subscribed, null);

    expect(rejoins, 1);
    expect(readies, 0);
  });

  test('끊김 없이 붙음이 또 와도 준비됨을 또 알린다 — 받는 쪽이 멱등이라 안전하다', () {
    listener(RealtimeSubscribeStatus.subscribed, null);
    listener(RealtimeSubscribeStatus.subscribed, null);

    expect(readies, 2);
    expect(rejoins, 0);
  });

  test('끊김 · closed 는 준비됨이 아니다', () {
    listener(RealtimeSubscribeStatus.channelError, null);
    listener(RealtimeSubscribeStatus.closed, null);

    expect(readies, 0);
  });

  test('콜백을 안 넘겨도 어떤 상태가 와도 던지지 않는다', () {
    final bare = channelStatusListener(onError: (_) {});

    for (final status in RealtimeSubscribeStatus.values) {
      bare(status, null);
    }
    bare(RealtimeSubscribeStatus.subscribed, null);
  });

  group('isPostgresReady — 서버가 postgres_changes 구독을 만들었다는 system 이벤트', () {
    test('postgres_changes 확장의 ok 면 준비됨이다', () {
      const payload = {
        'extension': 'postgres_changes',
        'message': 'Subscribed to PostgreSQL',
        'status': 'ok',
        'channel': 'messages:m1',
      };

      expect(isPostgresReady(payload), isTrue);
    });

    test('메시지가 없어도 확장이 postgres_changes 인 ok 면 준비됨이다 — 확장 조건이 홀로 선다', () {
      expect(isPostgresReady({'extension': 'postgres_changes', 'status': 'ok'}), isTrue);
    });

    test('확장 이름이 달라도 메시지가 "Subscribed to PostgreSQL" 인 ok 면 준비됨이다', () {
      expect(isPostgresReady({'status': 'ok', 'message': 'Subscribed to PostgreSQL'}), isTrue);
    });

    test('복제 연결 준비 알림(replication_ready 를 켠 채널)의 ok 도 준비됨이다', () {
      const payload = {
        'extension': 'system',
        'message': 'Replication connection established',
        'status': 'ok',
      };

      expect(isPostgresReady(payload), isTrue);
    });

    test('error 는 준비됨이 아니다 — 이 실패는 realtime_client 가 channelError 로 따로 올린다', () {
      const payload = {
        'extension': 'postgres_changes',
        'message': 'Subscribed to PostgreSQL',
        'status': 'error',
      };

      expect(isPostgresReady(payload), isFalse);
    });

    test('ok 여도 postgres 구독과 상관없는 system 이벤트는 준비됨이 아니다', () {
      expect(isPostgresReady({'extension': 'presence', 'status': 'ok', 'message': 'Joined'}), isFalse);
      expect(isPostgresReady({'status': 'ok'}), isFalse);
    });

    test('Map 이 아니거나 비어 있거나 값 타입이 이상해도 던지지 않고 false 다', () {
      expect(isPostgresReady(null), isFalse);
      expect(isPostgresReady('ok'), isFalse);
      expect(isPostgresReady(42), isFalse);
      expect(isPostgresReady(['status', 'ok']), isFalse);
      expect(isPostgresReady(const <String, Object?>{}), isFalse);
      expect(isPostgresReady({'status': 'ok', 'extension': 7, 'message': 7}), isFalse);
      expect(isPostgresReady({'status': null, 'extension': null, 'message': null}), isFalse);
    });
  });

  // RealtimeMessageStream 이 채널에 거는 system 걸이 — 채널을 켜지 않고 이 함수만으로 "ok 면 준비됨을 알린다" 를 확인한다.
  group('systemEventListener — system 이벤트를 받는 쪽의 준비됨 신호로 바꾼다', () {
    const ok = {'extension': 'postgres_changes', 'status': 'ok', 'message': 'Subscribed to PostgreSQL'};

    test('ok 이벤트면 준비됨을 알린다', () {
      systemEventListener(() => readies++)(ok);

      expect(readies, 1);
    });

    test('ok 가 아닌 이벤트는 알리지 않는다 — error · 상관없는 system 이벤트', () {
      final onSystem = systemEventListener(() => readies++);

      onSystem({'extension': 'postgres_changes', 'status': 'error', 'message': 'Subscribed to PostgreSQL'});
      onSystem({'extension': 'presence', 'status': 'ok', 'message': 'Joined'});

      expect(readies, 0);
    });

    test('Map 이 아니거나 값 타입이 이상해도 던지지 않고 알리지 않는다', () {
      final onSystem = systemEventListener(() => readies++);

      for (final weird in <Object?>[null, 'ok', 42, ['status', 'ok'], const <String, Object?>{}, {'status': 'ok', 'extension': 7, 'message': 7}]) {
        onSystem(weird);
      }

      expect(readies, 0);
    });

    test('onReady 를 안 넘겨도 어떤 이벤트가 와도 던지지 않는다', () {
      final onSystem = systemEventListener(null);

      onSystem(ok);
      onSystem(null);
      onSystem({'status': 'error'});
    });

    test('ok 가 여러 번 오면 그만큼 알린다 — 멱등은 받는 쪽 몫이다', () {
      final onSystem = systemEventListener(() => readies++);

      onSystem(ok);
      onSystem(ok);
      onSystem(ok);

      expect(readies, 3);
    });
  });
}
