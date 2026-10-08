import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_registrar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/model/fake_social_login_repository.dart';
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

  test('푸시 토큰 정리가 던져도 이 기기의 로그아웃은 한다', () async {
    // 탈퇴 리스너는 상태가 바뀔 때 한 번만 부른다 — 여기서 로그아웃을 건너뛰면
    // 사용자는 그 화면에 그대로 남고(auth_redirect 제자리), 앱을 다시 켜기 전에는 다시 시도할 길이 없다.
    final repository = FakeCardRepository(onDelete: () => throw StateError('push cleanup broke'));
    final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), repository);
    await registrar.start();
    final auth = MockGoTrueClient();
    when(() => auth.signOut()).thenAnswer((_) async {});

    await expectLater(signOut(registrar, auth), throwsStateError);

    verify(() => auth.signOut()).called(1);
  });

  group('소셜 공급자 로그아웃(후속 13 B-1)', () {
    test('앱 로그아웃 직후 카카오 · 구글 로그아웃을 부른다', () async {
      final order = <String>[];
      final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), FakeCardRepository());
      final auth = MockGoTrueClient();
      when(() => auth.signOut()).thenAnswer((_) async => order.add('signOut'));
      final social = _OrderedSocial(order);

      await signOut(registrar, auth, social: social);

      expect(order, ['signOut', 'providers']);
    });

    test('공급자 로그아웃이 던져도 앱 로그아웃은 끝나 있고 던지지 않는다', () async {
      final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), FakeCardRepository());
      final auth = MockGoTrueClient();
      when(() => auth.signOut()).thenAnswer((_) async {});

      await expectLater(signOut(registrar, auth, social: _ThrowingSocial()), completes);

      verify(() => auth.signOut()).called(1);
    });

    test('푸시 토큰 정리가 던져도 공급자 로그아웃까지 한다', () async {
      final repository = FakeCardRepository(onDelete: () => throw StateError('push cleanup broke'));
      final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), repository);
      await registrar.start();
      final auth = MockGoTrueClient();
      when(() => auth.signOut()).thenAnswer((_) async {});
      final social = FakeSocialLoginRepository();

      await expectLater(signOut(registrar, auth, social: social), throwsStateError);

      expect(social.signOutProvidersCalls, 1);
    });
  });
}

class _OrderedSocial extends FakeSocialLoginRepository {
  _OrderedSocial(this._order);

  final List<String> _order;

  @override
  Future<void> signOutProviders() async => _order.add('providers');
}

class _ThrowingSocial extends FakeSocialLoginRepository {
  @override
  Future<void> signOutProviders() async => throw StateError('kakao logout broke');
}
