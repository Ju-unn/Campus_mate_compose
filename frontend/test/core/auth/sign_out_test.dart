import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_registrar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../matching/model/fake_card_repository.dart';
import '../push/fake_push_messaging.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  test('푸시 토큰을 먼저 지우고 나서 로그아웃한다', () async {
    // 순서가 뒤집히면 DELETE /cards/push-tokens 가 세션 없이 나가서 401 로 끝나고,
    // 이 기기의 토큰이 서버에 죽은 채로 남는다.
    final order = <String>[];
    final repository = FakeCardRepository(onDelete: () => order.add('delete'));
    final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), repository);
    await registrar.start();

    final auth = MockGoTrueClient();
    when(() => auth.signOut()).thenAnswer((_) async {
      order.add('signOut');
    });

    await signOut(registrar, auth);

    expect(order, ['delete', 'signOut']);
    expect(repository.deletedTokens, ['tok-1']);
  });

  test('서버에 알리는 것이 네트워크 오류로 끝나도 던지지 않는다', () async {
    // gotrue 는 이 기기의 세션을 먼저 지우고 나서 서버에 알린다 — 그 알림이 실패해도 이미 로그아웃이다.
    // 던지면 시트를 닫은 뒤의 비동기 오류가 되어 화면이 아무것도 모른 채 로그만 남는다.
    final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), FakeCardRepository());
    final auth = MockGoTrueClient();
    when(() => auth.signOut()).thenThrow(AuthRetryableFetchException(message: 'offline'));

    await expectLater(signOut(registrar, auth), completes);
  });
}
