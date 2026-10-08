import 'package:campus_mate/auth/model/temporary_auth_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  setUpAll(() => registerFallbackValue(SignOutScope.local));

  late List<MockGoTrueClient> opened;
  late TemporaryAuthConnection connection;

  MockGoTrueClient newClient() {
    final client = MockGoTrueClient();
    when(() => client.signOut(scope: any(named: 'scope'))).thenAnswer((_) async {});
    opened.add(client);
    return client;
  }

  setUp(() {
    opened = [];
    connection = TemporaryAuthConnection(newClient);
  });

  test('처음 쓸 때 만들고, 닫기 전까지는 같은 연결을 쓴다', () {
    expect(opened, isEmpty, reason: '앱 시작이 아니라 필요할 때 만든다');

    final first = connection.open();
    final second = connection.open();

    expect(opened, hasLength(1));
    expect(identical(first, second), isTrue);
  });

  test('닫으면 이 기기에서만 로그아웃해 메모리 세션을 비우고, 다음엔 새로 만든다', () async {
    final first = connection.open() as MockGoTrueClient;

    await connection.close();
    final next = connection.open();

    verify(() => first.signOut(scope: SignOutScope.local)).called(1);
    verify(first.dispose).called(1);
    expect(identical(first, next), isFalse);
    expect(opened, hasLength(2));
  });

  test('연 적이 없으면 닫아도 아무것도 하지 않는다', () async {
    await connection.close();

    expect(opened, isEmpty);
  });

  test('로그아웃 요청이 실패해도 던지지 않고 연결을 버린다', () async {
    // gotrue 는 서버에 알리기 전에 메모리 세션부터 지운다 — 남은 것은 서버 알림뿐이다.
    final client = connection.open() as MockGoTrueClient;
    when(() => client.signOut(scope: any(named: 'scope'))).thenThrow(const AuthException('network'));

    await connection.close();

    verify(client.dispose).called(1);
    connection.open();
    expect(opened, hasLength(2));
  });
}
