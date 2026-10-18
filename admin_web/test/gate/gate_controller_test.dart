import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/config/admin_config.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/gate/gate_stage.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  ProviderContainer containerWith(FakeAdminAuth auth, FakeServer server, {AdminConfig config = completeConfig}) {
    final container = ProviderContainer(
      overrides: [
        adminConfigProvider.overrideWithValue(config),
        adminAuthProvider.overrideWithValue(auth),
        adminApiProvider.overrideWithValue(server.api()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  // 앱에서는 라우터가 늘 관문을 듣는다. 듣는 쪽이 없으면 Riverpod 3 은 무효가 된 provider 를 다시 만들지 않아
  // (판정 중 로그아웃 알림 → 무효) .future 가 끝나지 않는다 — 시험도 앱처럼 듣고 읽는다.
  Future<GateStage> stageOf(FakeAdminAuth auth, FakeServer server, {AdminConfig config = completeConfig}) {
    final container = containerWith(auth, server, config: config);
    final subscription = container.listen(gateProvider, (_, _) {});
    addTearDown(subscription.close);
    return container.read(gateProvider.future);
  }

  const aal2 = MfaState(aal2: true, factorId: 'factor-1');

  test('설정이 빠지면 Supabase 를 건드리지 않고 설정 누락으로 멈춘다', () async {
    const empty = AdminConfig(supabaseUrl: '', supabaseAnonKey: '', apiBaseUrl: '');
    final auth = FakeAdminAuth();

    final stage = await stageOf(auth, FakeServer(200), config: empty);

    expect(stage, isA<ConfigMissing>().having((s) => s.keys, 'keys', hasLength(3)));
    expect(auth.calls, isEmpty);
  });

  test('세션이 없으면 로그인', () async {
    final server = FakeServer(200);

    final stage = await stageOf(FakeAdminAuth(session: false), server);

    expect(stage, isA<SignedOut>());
    expect(server.requests, isEmpty);
  });

  test('등록한 TOTP 가 없으면 2단계 등록', () async {
    final stage = await stageOf(FakeAdminAuth(), FakeServer(200));

    expect(stage, isA<EnrollMfa>());
  });

  test('TOTP 가 있는데 aal1 이면 2단계 입력(그 factor 로)', () async {
    final auth = FakeAdminAuth(mfa: const MfaState(aal2: false, factorId: 'factor-1'));

    final stage = await stageOf(auth, FakeServer(200));

    expect(stage, isA<VerifyMfa>().having((s) => s.factorId, 'factorId', 'factor-1'));
  });

  test('aal2 에서 /admin/me 200 이면 준비 끝(관리자 메일과 함께)', () async {
    final server = FakeServer(200);

    final stage = await stageOf(FakeAdminAuth(mfa: aal2), server);

    expect(stage, isA<Ready>().having((s) => s.email, 'email', 'admin@example.com'));
    expect(server.requests.single.url.path, '/admin/me');
  });

  test('403 not_admin 이면 권한 없음', () async {
    final server = FakeServer(403, {'detail': AdminReason.notAdmin});

    expect(await stageOf(FakeAdminAuth(mfa: aal2), server), isA<NotAdmin>());
  });

  test('403 mfa_required 이면 2단계 필요(가진 factor 를 들고)', () async {
    final server = FakeServer(403, {'detail': AdminReason.mfaRequired});

    final stage = await stageOf(FakeAdminAuth(mfa: aal2), server);

    expect(stage, isA<MfaRequired>().having((s) => s.factorId, 'factorId', 'factor-1'));
  });

  test('401 이면 로그아웃하고 로그인으로', () async {
    final auth = FakeAdminAuth(mfa: aal2);

    final stage = await stageOf(auth, FakeServer(401));

    expect(stage, isA<SignedOut>());
    expect(auth.calls, contains('signOut'));
  });

  test('서버 오류 · 연결 실패는 연결 안 됨', () async {
    expect(await stageOf(FakeAdminAuth(mfa: aal2), FakeServer(500)), isA<Unavailable>());
  });

  test('로그인 상태가 바뀌면 다시 판정한다', () async {
    final auth = FakeAdminAuth(session: false);
    final container = containerWith(auth, FakeServer(200));
    final subscription = container.listen(gateProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(await container.read(gateProvider.future), isA<SignedOut>());

    auth
      ..session = true
      ..emitChange();
    await pumpEventQueue(); // 알림은 다음 차례에 닿는다

    expect(await container.read(gateProvider.future), isA<EnrollMfa>());
  });

  test('2단계 필요 화면에서 코드 입력으로 넘어간다(factor 가 없으면 등록)', () async {
    final container = containerWith(FakeAdminAuth(), FakeServer(200));
    await container.read(gateProvider.future);
    final controller = container.read(gateProvider.notifier);

    controller.startMfa(const MfaRequired('factor-1'));
    expect(container.read(gateProvider).value, isA<VerifyMfa>());

    controller.startMfa(const MfaRequired(null));
    expect(container.read(gateProvider).value, isA<EnrollMfa>());
  });
}
