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
  });
}
