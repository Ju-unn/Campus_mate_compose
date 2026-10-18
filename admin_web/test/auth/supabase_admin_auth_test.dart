import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/auth/supabase_admin_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockGoTrue extends Mock implements GoTrueClient {}

class _MockMfa extends Mock implements GoTrueMFAApi {}

Factor _factor(String id, FactorStatus status) => Factor(
      id: id,
      friendlyName: null,
      factorType: FactorType.totp,
      status: status,
      createdAt: DateTime(2026, 10, 18),
      updatedAt: DateTime(2026, 10, 18),
    );

AuthMFAListFactorsResponse _factors(List<Factor> all) => AuthMFAListFactorsResponse(
      all: all,
      totp: all.where((f) => f.status == FactorStatus.verified).toList(),
      phone: const [],
      webauthn: const [],
    );

AuthMFAGetAuthenticatorAssuranceLevelResponse _level(AuthenticatorAssuranceLevels level) =>
    AuthMFAGetAuthenticatorAssuranceLevelResponse(currentLevel: level, nextLevel: level, currentAuthenticationMethods: const []);

void main() {
  late _MockGoTrue goTrue;
  late _MockMfa mfa;
  late StreamController<AuthState> events;
  late SupabaseAdminAuth auth;

  setUpAll(() => registerFallbackValue(FactorType.totp));

  setUp(() {
    goTrue = _MockGoTrue();
    mfa = _MockMfa();
    events = StreamController<AuthState>();
    when(() => goTrue.mfa).thenReturn(mfa);
    when(() => goTrue.onAuthStateChange).thenAnswer((_) => events.stream);
    auth = SupabaseAdminAuth(goTrue);
    addTearDown(auth.dispose);
  });

  test('aal 은 토큰에서, 확인된 TOTP 는 목록에서 읽는다', () async {
    when(() => mfa.listFactors()).thenAnswer((_) async => _factors([_factor('f-1', FactorStatus.verified)]));
    when(() => mfa.getAuthenticatorAssuranceLevel()).thenReturn(_level(AuthenticatorAssuranceLevels.aal1));

    final state = await auth.mfaState();

    expect(state.aal2, isFalse);
    expect(state.factorId, 'f-1');
  });

  test('등록 전에 끝내지 못한(확인 안 된) TOTP 를 지우고 새로 만든다', () async {
    when(() => mfa.listFactors()).thenAnswer(
      (_) async => _factors([_factor('stale', FactorStatus.unverified), _factor('ok', FactorStatus.verified)]),
    );
    when(() => mfa.unenroll(any())).thenAnswer((_) async => const AuthMFAUnenrollResponse(id: 'stale'));
    when(() => mfa.enroll(factorType: any(named: 'factorType'), issuer: any(named: 'issuer'))).thenAnswer(
      (_) async => const AuthMFAEnrollResponse(
        id: 'new',
        type: FactorType.totp,
        totp: TOTPEnrollment(qrCode: 'svg', secret: 'SECRET', uri: 'otpauth://x'),
        phone: null,
      ),
    );

    final enrollment = await auth.enrollTotp();

    verify(() => mfa.unenroll('stale')).called(1);
    verifyNever(() => mfa.unenroll('ok'));
    expect(enrollment.factorId, 'new');
    expect(enrollment.secret, 'SECRET');
  });

  test('코드 확인: 성공 · 틀린 코드 · 연결 실패를 가른다', () async {
    when(() => mfa.challengeAndVerify(factorId: 'f', code: '111111')).thenAnswer((_) async => throw const AuthApiException('Invalid TOTP code entered', statusCode: '422'));
    when(() => mfa.challengeAndVerify(factorId: 'f', code: '222222')).thenAnswer((_) async => throw AuthRetryableFetchException());

    expect(await auth.verifyTotp(factorId: 'f', code: '111111'), VerifyOutcome.wrongCode);
    expect(await auth.verifyTotp(factorId: 'f', code: '222222'), VerifyOutcome.failed);
  });

  test('관문에 필요한 사건만 알린다(토큰 갱신 · 첫 세션은 빼고)', () async {
    var count = 0;
    final subscription = auth.changes.listen((_) => count++);
    addTearDown(subscription.cancel);

    for (final event in AuthChangeEvent.values) {
      events.add(AuthState(event, null));
    }
    await pumpEventQueue();

    expect(count, 3); // signedIn · signedOut · mfaChallengeVerified
  });

  group('구글 로그인 복귀 주소 판정(보안 검토 낮음 7)', () {
    bool handles(String url) => isPkceAuthCallback(Uri.parse('https://admin.test$url'));

    test('PKCE 복귀(?code=) · 실패 복귀(?error=)만 세션 교환으로 넘긴다', () {
      expect(handles('/?code=abc'), isTrue);
      expect(handles('/?error=access_denied&error_code=403&error_description=x'), isTrue);
    });

    test('#access_token= 조각(implicit)은 넘기지 않는다 — 링크로 남의 세션을 심지 못한다', () {
      expect(handles('/#access_token=evil&refresh_token=r&expires_in=3600&token_type=bearer'), isFalse);
      expect(handles('/heart-tasks/1#access_token=evil&refresh_token=r&expires_in=3600&token_type=bearer'), isFalse);
      expect(handles('/?access_token=evil&refresh_token=r&expires_in=3600&token_type=bearer'), isFalse);
    });

    test('조각에만 code · error 가 있어도 넘기지 않는다', () {
      expect(handles('/#code=abc'), isFalse);
      expect(handles('/#error=x'), isFalse);
    });

    test('보통 화면 주소 · 다른 쿼리는 넘기지 않는다', () {
      expect(handles('/heart-tasks/abc'), isFalse);
      expect(handles('/reports?status=open'), isFalse);
    });
  });
}
