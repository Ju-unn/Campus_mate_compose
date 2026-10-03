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

    test('기기 토큰 버리기도 실패하면 될 때까지 다시 한다', () async {
      final messaging = FakePushMessaging(token: 'tok-1')..deleteTokenFailures = 2;
      final repository = FakeCardRepository();
      final registrar = PushRegistrar(messaging, repository, retryDelay: const Duration(milliseconds: 1));
      await registrar.start();
      repository.writeResult = const FailureResult(NetworkFailure());

      await registrar.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(messaging.deleteTokenCalls, 3);
      expect(messaging.deletedOnDevice, 1);
    });

    test('그사이 다시 로그인해 등록되면 다시 하기를 멈춘다 — 새 주인의 토큰을 버리면 안 된다', () async {
      final messaging = FakePushMessaging(token: 'tok-1')..deleteTokenFailures = 1000;
      final repository = FakeCardRepository();
      final registrar = PushRegistrar(messaging, repository, retryDelay: const Duration(milliseconds: 5));
      await registrar.start();
      repository.writeResult = const FailureResult(NetworkFailure());
      await registrar.stop();
      repository.writeResult = const Success(null);

      await registrar.start();
      final callsAfterLogin = messaging.deleteTokenCalls;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repository.registeredTokens, ['tok-1', 'tok-1']);
      expect(messaging.deleteTokenCalls, callsAfterLogin);
    });
  });
}
