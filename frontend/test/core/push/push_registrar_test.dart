import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/push/push_registrar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../matching/model/fake_card_repository.dart';
import 'fake_push_messaging.dart';

void main() {
  test('토큰을 받으면 서버에 등록한다', () async {
    final messaging = FakePushMessaging(token: 'tok-1');
    final repository = FakeCardRepository();

    await PushRegistrar(messaging, repository).start();

    expect(repository.registeredTokens, ['tok-1']);
  });

  test('권한을 거부하면 토큰을 묻지도 않는다', () async {
    final messaging = FakePushMessaging(token: 'tok-1', granted: false);
    final repository = FakeCardRepository();

    await PushRegistrar(messaging, repository).start();

    expect(repository.registeredTokens, isEmpty);
  });

  test('등록이 막히면 다음 start() 에서 다시 보낸다', () async {
    // 새로 가입한 사용자는 학생 인증 전이라 서버가 403 을 준다 —
    // 인증 게이트가 열린 뒤 main.dart 가 다시 부르면 그때 등록돼야 한다.
    final messaging = FakePushMessaging(token: 'tok-1');
    final repository = FakeCardRepository()..writeResult = const FailureResult(UnknownFailure());
    final registrar = PushRegistrar(messaging, repository);
    await registrar.start();
    repository.writeResult = const Success(null);

    await registrar.start();

    expect(repository.registeredTokens, ['tok-1', 'tok-1']);
  });

  test('이미 등록했으면 start() 를 다시 불러도 보내지 않는다', () async {
    final messaging = FakePushMessaging(token: 'tok-1');
    final repository = FakeCardRepository();
    final registrar = PushRegistrar(messaging, repository);
    await registrar.start();

    await registrar.start();

    expect(repository.registeredTokens, ['tok-1']);
  });

  test('토큰이 갱신되면 새 토큰도 등록한다', () async {
    final messaging = FakePushMessaging(token: 'tok-1');
    final repository = FakeCardRepository();
    await PushRegistrar(messaging, repository).start();

    messaging.emitRefreshedToken('tok-2');
    await Future<void>.delayed(Duration.zero);

    expect(repository.registeredTokens, ['tok-1', 'tok-2']);
  });

  test('로그아웃하면 그 기기의 토큰을 지운다 — 다음 사람에게 내 알림이 가면 안 된다', () async {
    final messaging = FakePushMessaging(token: 'tok-1');
    final repository = FakeCardRepository();
    final registrar = PushRegistrar(messaging, repository);
    await registrar.start();

    await registrar.stop();

    expect(repository.deletedTokens, ['tok-1']);
    // 서버에서 지웠으면 기기 토큰은 그대로 둔다 — 다음 로그인이 같은 토큰을 다시 등록한다.
    expect(messaging.deleteTokenCalls, 0);
  });

  group('서버에서 못 지우면 기기의 토큰을 버린다(A15)', () {
    test('인터넷 없이 로그아웃하면 서버 삭제 대신 기기 토큰을 버린다', () async {
      final messaging = FakePushMessaging(token: 'tok-1');
      final repository = FakeCardRepository();
      final registrar = PushRegistrar(messaging, repository);
      await registrar.start();
      repository.writeResult = const FailureResult(NetworkFailure());

      await registrar.stop();
      await Future<void>.delayed(Duration.zero);

      expect(repository.deletedTokens, ['tok-1']);
      expect(messaging.deletedOnDevice, 1);
    });

    test('세션이 이미 끝나 서버가 받지 않아도 기기 토큰을 버린다', () async {
      final messaging = FakePushMessaging(token: 'tok-1');
      final repository = FakeCardRepository();
      final registrar = PushRegistrar(messaging, repository);
      await registrar.start();
      repository.writeResult = const FailureResult(SessionExpiredFailure());

      await registrar.stop();
      await Future<void>.delayed(Duration.zero);

      expect(messaging.deletedOnDevice, 1);
    });

    test('서버 삭제가 끝나지 않으면 기다리다 실패로 보고 기기 토큰을 버린다', () async {
      // 앱 http 에는 타임아웃이 없다 — 매달린 DELETE 를 기다리면 로그아웃(signOut 의 finally)까지 못 간다.
      final messaging = FakePushMessaging(token: 'tok-1');
      final registrar = PushRegistrar(
        messaging,
        _HangingDeleteRepository(),
        deleteTimeout: const Duration(milliseconds: 50),
      );
      await registrar.start();

      await registrar.stop();
      await Future<void>.delayed(Duration.zero);

      expect(messaging.deletedOnDevice, 1);
    }, timeout: const Timeout(Duration(seconds: 2)));

    test('로그아웃은 기기 토큰 버리기를 기다리지 않고, 그사이 다시 로그인하면 버린 뒤에 토큰을 받는다', () async {
      // 느린 망에서 로그아웃 화면이 FCM 을 기다리며 멈추지 않게 · 곧 버려질 토큰을 새 주인으로 등록하지 않게.
      final gate = Completer<void>();
      final messaging = FakePushMessaging(token: 'tok-1');
      final repository = FakeCardRepository();
      final registrar = PushRegistrar(messaging, repository);
      await registrar.start();
      messaging.deleteTokenGate = gate;
      repository.writeResult = const FailureResult(NetworkFailure());

      await registrar.stop().timeout(const Duration(seconds: 1));
      repository.writeResult = const Success(null);
      final login = registrar.start();
      await Future<void>.delayed(Duration.zero);

      expect(repository.registeredTokens, ['tok-1']);
      gate.complete();
      await login;

      expect(messaging.getTokenAfterDeletes, [0, 1]);
      expect(repository.registeredTokens, ['tok-1', 'tok-1']);
    });

    // 다시 하기 간격을 0 으로 두고 이벤트 큐만 비운다 — 실제 시계(몇 ms)를 기다리면 기기가 바쁠 때 흔들린다.
    test('기기 토큰 버리기도 실패하면 될 때까지 다시 한다', () async {
      final messaging = FakePushMessaging(token: 'tok-1')..deleteTokenFailures = 2;
      final repository = FakeCardRepository();
      final registrar = PushRegistrar(messaging, repository, retryDelay: Duration.zero);
      await registrar.start();
      repository.writeResult = const FailureResult(NetworkFailure());

      await registrar.stop();
      await pumpEventQueue();

      expect(messaging.deleteTokenCalls, 3);
      expect(messaging.deletedOnDevice, 1);
    });

    test('그사이 다시 로그인해 등록되면 다시 하기를 멈춘다 — 새 주인의 토큰을 버리면 안 된다', () async {
      final messaging = FakePushMessaging(token: 'tok-1')..deleteTokenFailures = 1000;
      final repository = FakeCardRepository();
      final registrar = PushRegistrar(messaging, repository, retryDelay: Duration.zero);
      await registrar.start();
      repository.writeResult = const FailureResult(NetworkFailure());
      await registrar.stop();
      repository.writeResult = const Success(null);

      await registrar.start();
      final callsAfterLogin = messaging.deleteTokenCalls;
      await pumpEventQueue();

      expect(repository.registeredTokens, ['tok-1', 'tok-1']);
      expect(messaging.deleteTokenCalls, callsAfterLogin);
    });
  });

  // L1: 등록한 토큰을 기억하지 못해도 서버에 그 토큰이 남아 있을 수 있다. 남기면 다음에 이 폰으로 로그인한 사람에게
  // 앞 계정의 알림이 간다. 그래서 모르면 기기에서 토큰을 읽어 서버에서 지우고, 그것도 안 되면 기기 토큰을 버린다.
  group('로그아웃 때 등록한 토큰을 모르면 기기에서 읽어 지운다(L1)', () {
    test('알림 권한을 끈 기기도 로그아웃하면 예전 세션이 서버에 남긴 토큰을 지운다', () async {
      final server = _ServerRepository()..serverTokens.add('tok-1');
      final messaging = FakePushMessaging(token: 'tok-1', granted: false);
      final registrar = PushRegistrar(messaging, server);
      await registrar.start();

      await registrar.stop();

      expect(server.serverTokens, isEmpty);
      // 서버에서 지웠으면 기기 토큰은 그대로 둔다 — 권한을 다시 켜고 로그인하면 같은 토큰을 다시 등록한다.
      expect(messaging.deleteTokenCalls, 0);
    });

    test('등록 응답이 끊겨 토큰을 기억하지 못해도 로그아웃하면 서버에서 지운다', () async {
      // 서버는 받아 저장했는데 응답이 끊겨 앱은 실패로 본 경우.
      final server = _ServerRepository(registerResult: const FailureResult(NetworkFailure()));
      final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), server);
      await registrar.start();
      expect(server.serverTokens, {'tok-1'}, reason: '앱은 실패로 봤지만 서버에는 들어가 있다');

      await registrar.stop();

      expect(server.serverTokens, isEmpty);
    });

    test('등록 요청이 날아가는 중에 로그아웃하면 요청이 서버에 닿을 때까지 기다렸다가 그 토큰을 지운다', () async {
      // 기다리지 않으면 stop() 이 "모른다" 로 끝나고, 요청이 로그아웃 뒤에 서버에 닿아 토큰이 남는다.
      final gate = Completer<void>();
      final messaging = FakePushMessaging(token: 'tok-1');
      final server = _ServerRepository(registerGate: gate);
      final registrar = PushRegistrar(messaging, server);
      final login = registrar.start();
      await pumpEventQueue();

      final logout = registrar.stop();
      await pumpEventQueue();
      expect(server.deletedTokens, isEmpty, reason: '요청이 서버에 닿기 전에 지우면, 그 뒤에 닿은 토큰이 남는다');
      gate.complete();
      await Future.wait([login, logout]);

      expect(server.serverTokens, isEmpty);
      // 기다리는 사이 닿은 등록 성공은 기억한다 — 기기에 다시 묻지 않고 그 토큰을 지운다.
      expect(messaging.getTokenAfterDeletes, hasLength(1), reason: 'start() 때 한 번뿐');
    });

    test('찾은 토큰을 서버에서 못 지우면 기기 토큰을 버린다', () async {
      final server = _ServerRepository()..serverTokens.add('tok-1');
      final messaging = FakePushMessaging(token: 'tok-1', granted: false);
      final registrar = PushRegistrar(messaging, server);
      await registrar.start();
      server.writeResult = const FailureResult(NetworkFailure());

      await registrar.stop();
      await pumpEventQueue();

      expect(server.deletedTokens, ['tok-1']);
      expect(messaging.deletedOnDevice, 1);
    });

    test('날아가던 등록이 던지고 끝나도 로그아웃은 기기에서 읽은 토큰을 서버에서 지운다', () async {
      final gate = Completer<void>();
      final server = _ServerRepository()..serverTokens.add('tok-1');
      final registrar = PushRegistrar(_FailingPermissionMessaging(gate), server);
      final loginFailure = expectLater(registrar.start(), throwsException);
      await pumpEventQueue();

      final logout = registrar.stop();
      await pumpEventQueue();
      expect(server.deletedTokens, isEmpty, reason: '진행 중인 등록이 끝나기 전에는 지우러 가지 않는다');
      gate.complete();
      await Future.wait([loginFailure, logout]);

      expect(server.serverTokens, isEmpty);
    });

    test('등록이 끝나지 않아도 로그아웃은 기다리다 넘어가고 기기 토큰을 버린다', () async {
      // 앱 http 에는 타임아웃이 없다 — 매달린 등록을 끝까지 기다리면 로그아웃(signOut 의 finally)까지 못 간다.
      final messaging = FakePushMessaging(token: 'tok-1');
      final server = _ServerRepository(registerGate: Completer<void>());
      final registrar = PushRegistrar(messaging, server, deleteTimeout: Duration.zero);
      unawaited(registrar.start());
      await pumpEventQueue();

      await registrar.stop();
      await pumpEventQueue();

      expect(messaging.deletedOnDevice, 1);
    }, timeout: const Timeout(Duration(seconds: 2)));

    test('기기에서 토큰을 읽어 오지 못하면(null) 기기 토큰을 버린다', () async {
      final messaging = _ScriptedTokenMessaging(() async => null);
      final registrar = PushRegistrar(messaging, _ServerRepository());
      await registrar.start();

      await registrar.stop();
      await pumpEventQueue();

      expect(messaging.deletedOnDevice, 1);
    });

    test('기기에서 토큰을 읽다 던져도 로그아웃은 끝나고 기기 토큰을 버린다', () async {
      final messaging = _ScriptedTokenMessaging(() async => throw Exception('SERVICE_NOT_AVAILABLE'));
      final registrar = PushRegistrar(messaging, _ServerRepository());
      await registrar.start();

      await expectLater(registrar.stop(), completes);
      await pumpEventQueue();

      expect(messaging.deletedOnDevice, 1);
    });

    test('기기에서 토큰을 읽는 데 끝이 없으면 기다리다 넘어가고 기기 토큰을 버린다', () async {
      final messaging = _ScriptedTokenMessaging(() => Completer<String?>().future);
      final registrar = PushRegistrar(messaging, _ServerRepository(), deleteTimeout: Duration.zero);
      await registrar.start();

      await registrar.stop();
      await pumpEventQueue();

      expect(messaging.deletedOnDevice, 1);
    }, timeout: const Timeout(Duration(seconds: 2)));

    test('찾는 데 쓴 시간은 서버 삭제 시간에서 뺀다 — 로그아웃 최악 대기는 deleteTimeout 하나다', () async {
      const budget = Duration(milliseconds: 300);
      final messaging = _ScriptedTokenMessaging(
        () => Future<String?>.delayed(const Duration(milliseconds: 200), () => 'tok-1'),
      );
      final registrar = PushRegistrar(messaging, _HangingDeleteRepository(), deleteTimeout: budget);
      await registrar.start();
      final clock = Stopwatch()..start();

      await registrar.stop();
      clock.stop();
      await pumpEventQueue();

      // 나눠 쓰지 않으면 찾기 200ms + 삭제 300ms = 500ms 를 기다린다.
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 450)));
      expect(messaging.deletedOnDevice, 1);
    }, timeout: const Timeout(Duration(seconds: 3)));

    test('찾기가 시간을 다 쓰면 서버 삭제는 보내지 않고 바로 기기 토큰을 버린다', () async {
      final messaging = FakePushMessaging(token: 'tok-1');
      final server = _ServerRepository();
      final registrar = PushRegistrar(messaging, server, deleteTimeout: Duration.zero);
      await registrar.start();

      await registrar.stop();
      await pumpEventQueue();

      expect(server.deletedTokens, isEmpty);
      expect(messaging.deletedOnDevice, 1);
    });

    test('로그아웃 뒤 토큰이 갱신돼도 등록하지 않는다 — 다음 사람 세션으로 앞 기기 토큰이 나가면 안 된다', () async {
      final messaging = FakePushMessaging(token: 'tok-1');
      final server = _ServerRepository();
      final registrar = PushRegistrar(messaging, server);
      await registrar.start();
      await registrar.stop();

      messaging.emitRefreshedToken('tok-2');
      await pumpEventQueue();

      expect(server.serverTokens, isNot(contains('tok-2')));
    });

    test('등록이 날아가는 중에 로그아웃해도 그 등록이 끝난 뒤에 갱신 구독을 끊는다', () async {
      // 등록이 끝나면 구독이 새로 걸린다 — 기다리기 전에 끊으면 그 구독이 로그아웃 뒤까지 살아남는다.
      final gate = Completer<void>();
      final messaging = FakePushMessaging(token: 'tok-1');
      final server = _ServerRepository(registerGate: gate);
      final registrar = PushRegistrar(messaging, server);
      final login = registrar.start();
      await pumpEventQueue();
      final logout = registrar.stop();
      gate.complete();
      await Future.wait([login, logout]);

      messaging.emitRefreshedToken('tok-2');
      await pumpEventQueue();

      expect(server.serverTokens, isNot(contains('tok-2')));
    });

    test('매달렸던 등록이 로그아웃 뒤에 성공해도 기기 토큰 버리기를 멈추게 하지 않는다', () async {
      // 늦은 성공이 "새 주인이 등록했다" 로 읽혀 다시 하기를 취소하면, 앞 계정의 토큰이 서버와 기기에 그대로 남는다.
      final gate = Completer<void>();
      final messaging = FakePushMessaging(token: 'tok-1')..deleteTokenFailures = 1000;
      addTearDown(() => messaging.deleteTokenFailures = 0); // 다시 하기가 끝없이 돌지 않게
      final server = _ServerRepository(registerGate: gate);
      final registrar = PushRegistrar(messaging, server, deleteTimeout: Duration.zero, retryDelay: Duration.zero);
      unawaited(registrar.start());
      await pumpEventQueue();
      await registrar.stop();
      await pumpEventQueue();

      gate.complete();
      await pumpEventQueue();
      final callsAfterLateSuccess = messaging.deleteTokenCalls;
      await pumpEventQueue();

      expect(messaging.deleteTokenCalls, greaterThan(callsAfterLateSuccess));
    }, timeout: const Timeout(Duration(seconds: 2)));

    test('등록한 토큰을 알면 기기에 다시 묻지 않는다', () async {
      final messaging = FakePushMessaging(token: 'tok-1');
      final registrar = PushRegistrar(messaging, _ServerRepository());
      await registrar.start();

      await registrar.stop();

      expect(messaging.getTokenAfterDeletes, hasLength(1), reason: 'start() 때 한 번뿐');
    });

    test('로그아웃 뒤 한 번 더 불려도 아무것도 하지 않는다 — 세션이 끝난 뒤의 뒷정리가 기기 토큰을 버리면 안 된다', () async {
      // main.dart 는 signOut() 이 stop() 을 부른 뒤 세션이 사라지면 한 번 더 stop() 을 부른다.
      final messaging = FakePushMessaging(token: 'tok-1');
      final server = _ServerRepository();
      final registrar = PushRegistrar(messaging, server);
      await registrar.start();
      await registrar.stop();

      await registrar.stop();
      await pumpEventQueue();

      expect(server.deletedTokens, ['tok-1']);
      expect(messaging.getTokenAfterDeletes, hasLength(1));
      expect(messaging.deleteTokenCalls, 0);
    });

    test('로그아웃이 겹쳐 두 번 불려도 서버 삭제와 기기 토큰 읽기는 한 번씩이다', () async {
      final messaging = FakePushMessaging(token: 'tok-1', granted: false);
      final server = _ServerRepository();
      final registrar = PushRegistrar(messaging, server);
      await registrar.start();

      await Future.wait([registrar.stop(), registrar.stop()]);

      expect(server.deletedTokens, ['tok-1']);
      expect(messaging.getTokenAfterDeletes, hasLength(1));
    });

    test('로그아웃이 겹쳐 불려도 서버 삭제가 실패하면 기기 토큰은 한 번만 버린다', () async {
      final messaging = FakePushMessaging(token: 'tok-1', granted: false);
      final server = _ServerRepository();
      final registrar = PushRegistrar(messaging, server);
      await registrar.start();
      server.writeResult = const FailureResult(NetworkFailure());

      await Future.wait([registrar.stop(), registrar.stop()]);
      await pumpEventQueue();

      expect(messaging.deleteTokenCalls, 1);
      expect(messaging.deletedOnDevice, 1);
    });

    test('서버 삭제가 진행 중일 때 불린 두 번째 로그아웃도 첫 번째가 끝나야 끝난다', () async {
      final gate = Completer<void>();
      final server = _ServerRepository(deleteGate: gate);
      final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), server);
      await registrar.start();
      final first = registrar.stop();
      await pumpEventQueue();
      var secondDone = false;
      final second = registrar.stop().then((_) => secondDone = true);
      await pumpEventQueue();
      expect(secondDone, isFalse, reason: '첫 번째 서버 삭제가 아직 안 끝났다');

      gate.complete();
      await Future.wait([first, second]);

      expect(server.deletedTokens, ['tok-1']);
    });

    test('로그아웃 뒤 다시 로그인하면 다음 로그아웃도 서버에서 지운다', () async {
      // 끝난 로그아웃이 _stopping 을 비워 두지 않으면 두 번째 stop() 이 옛 결과를 돌려받아 아무것도 지우지 않는다.
      final messaging = FakePushMessaging(token: 'tok-1');
      final server = _ServerRepository();
      final registrar = PushRegistrar(messaging, server);
      await registrar.start();
      await registrar.stop();
      await registrar.start();

      await registrar.stop();

      expect(server.deletedTokens, ['tok-1', 'tok-1']);
    });

    test('start() 를 부른 적이 없으면 stop() 은 서버에도 기기에도 손대지 않는다', () async {
      final messaging = FakePushMessaging(token: 'tok-1');
      final server = _ServerRepository();

      await PushRegistrar(messaging, server).stop();

      expect(server.deletedTokens, isEmpty);
      expect(messaging.getTokenAfterDeletes, isEmpty);
      expect(messaging.deleteTokenCalls, 0);
    });
  });
}

class _HangingDeleteRepository extends FakeCardRepository {
  @override
  Future<Result<void>> deletePushToken(String token) => Completer<Result<void>>().future;
}

/// 서버가 들고 있는 토큰([serverTokens])을 흉내 낸다 — 요청이 서버에 "닿은 순간" 에 들어가고 지워진다.
class _ServerRepository extends FakeCardRepository {
  _ServerRepository({this.registerGate, this.registerResult, this.deleteGate});

  /// 있으면 등록 요청이 이것이 끝나야 서버에 닿는다(날아가는 중).
  final Completer<void>? registerGate;

  /// 있으면 삭제 요청이 이것이 끝나야 서버에 닿는다(날아가는 중).
  final Completer<void>? deleteGate;

  /// 있으면 서버는 토큰을 저장하지만 앱에는 이 결과가 돌아온다(응답이 끊긴 경우).
  final Result<void>? registerResult;

  final Set<String> serverTokens = {};

  @override
  Future<Result<void>> registerPushToken(String token) async {
    await registerGate?.future;
    serverTokens.add(token);
    final result = await super.registerPushToken(token);
    return registerResult ?? result;
  }

  @override
  Future<Result<void>> deletePushToken(String token) async {
    await deleteGate?.future;
    serverTokens.remove(token);
    return super.deletePushToken(token);
  }
}

/// 권한 묻기가 [gate] 가 열린 뒤 던진다 — 등록이 날아가는 중에 플랫폼 오류로 끝나는 경우.
class _FailingPermissionMessaging extends FakePushMessaging {
  _FailingPermissionMessaging(this.gate) : super(token: 'tok-1');

  final Completer<void> gate;

  @override
  Future<bool> requestPermission() async {
    await gate.future;
    throw Exception('PLATFORM_ERROR');
  }
}

/// 권한은 거부된 기기 — start() 는 토큰을 묻지 않고, stop() 이 처음으로 [getToken] 을 부른다.
class _ScriptedTokenMessaging extends FakePushMessaging {
  _ScriptedTokenMessaging(this._onGetToken) : super(token: 'unused', granted: false);

  final Future<String?> Function() _onGetToken;

  @override
  Future<String?> getToken() => _onGetToken();
}
