import 'package:campus_mate_admin/gate/gate_stage.dart';
import 'package:campus_mate_admin/router/admin_router.dart';
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ready = Ready('admin@example.com');

  String? go(GateRedirector redirector, GateStage? stage, String location) {
    return redirector.redirect(stage, Uri.parse(location));
  }

  test('판정 전에는 어느 주소든 불러오는 중으로', () {
    final r = GateRedirector();

    expect(go(r, null, '/reports'), GatePaths.loading);
    expect(go(r, null, GatePaths.loading), isNull);
  });

  test('단계마다 정해진 화면으로 보내고, 이미 거기면 그대로 둔다', () {
    final cases = <GateStage, String>{
      const ConfigMissing(['SUPABASE_URL']): GatePaths.setup,
      const SignedOut(): GatePaths.login,
      const EnrollMfa(): GatePaths.enroll,
      const VerifyMfa('f'): GatePaths.verify,
      const MfaRequired('f'): GatePaths.mfaRequired,
      const NotAdmin(): GatePaths.forbidden,
      const Unavailable(): GatePaths.unavailable,
    };
    for (final entry in cases.entries) {
      final r = GateRedirector();
      expect(go(r, entry.key, '/reports'), entry.value, reason: '${entry.key}');
      expect(go(r, entry.key, entry.value), isNull, reason: '${entry.key}');
    }
  });

  test('준비가 끝나면 메뉴 화면은 그대로, 관문 화면 · 모르는 주소는 홈으로', () {
    final r = GateRedirector();

    expect(go(r, ready, AdminSection.reports.path), isNull);
    expect(go(r, ready, GatePaths.login), AdminSection.home.path);
    expect(go(r, ready, '/nope'), AdminSection.home.path);
  });

  test('처음 연 메뉴 주소(쿼리 포함)를 기억했다가 판정이 끝나면 그리로 보낸다', () {
    final r = GateRedirector();

    expect(go(r, null, '/reports?status=open'), GatePaths.loading);
    expect(go(r, ready, GatePaths.loading), '/reports?status=open');
    expect(go(r, ready, '/reports?status=open'), isNull);
    // 한 번 돌려보낸 뒤에는 잊는다
    expect(go(r, ready, GatePaths.login), AdminSection.home.path);
  });

  test('관문(2단계 입력)을 거쳐도 처음 주소로 돌아간다', () {
    final r = GateRedirector();

    expect(go(r, null, '/heart-tasks'), GatePaths.loading);
    expect(go(r, const VerifyMfa('f'), GatePaths.loading), GatePaths.verify);
    expect(go(r, ready, GatePaths.verify), '/heart-tasks');
  });

  test('메뉴 아래 주소(디스코드 알림 링크 /reports/{id})도 메뉴 주소로 기억한다', () {
    final r = GateRedirector();

    expect(go(r, null, '/reports/123'), GatePaths.loading);
    expect(go(r, ready, GatePaths.loading), '/reports/123');
    expect(go(r, ready, '/reports/123'), isNull);
  });

  test('관문 화면 · 바깥 주소는 기억하지 않고 홈으로', () {
    final r = GateRedirector();

    expect(go(r, null, GatePaths.login), GatePaths.loading);
    expect(go(r, null, '/nope'), GatePaths.loading);
    expect(go(r, ready, GatePaths.loading), AdminSection.home.path);
  });

  test('구글 로그인 복귀 매개변수(?code= 등)는 판정이 끝나면 지운다(다른 쿼리는 남긴다)', () {
    final r = GateRedirector();

    expect(go(r, ready, '/?code=abc'), AdminSection.home.path);
    expect(go(r, ready, '/reports?status=open&error=access_denied&error_description=x'), '/reports?status=open');
    expect(go(r, ready, '/reports?status=open'), isNull);
  });

  test('관문을 거칠 때도 기억하는 주소에서 복귀 매개변수를 뺀다', () {
    final r = GateRedirector();

    expect(go(r, null, '/reports?code=abc'), GatePaths.loading);
    expect(go(r, ready, GatePaths.loading), '/reports');
  });

  test('왼쪽 메뉴는 졸업생(3번째)을 포함해 9개, pen A10 순서', () {
    expect(
      AdminSection.values.map((s) => s.label),
      ['홈', '인증샷 검수', '졸업생', '신고', '매칭', '사용자', '결제', '미등록 학교 메일', '작업 기록'],
    );
    expect(AdminSection.matching.path, '/matching');
    expect(AdminSection.graduates.path, '/graduates');
    expect(AdminSection.values.map((s) => s.path).toSet(), hasLength(9));
  });

  test('구글 로그인이 실패해 돌아오면(?error=) 로그인 화면에 실패 표시를 달아 보낸다', () {
    final r = GateRedirector();

    expect(go(r, const SignedOut(), '/?error=access_denied&error_description=x'), '/login?failed=1');
    expect(go(r, const SignedOut(), '/login?failed=1'), isNull);
    expect(go(r, const SignedOut(), '/'), GatePaths.login);
  });

  test('실패 표시는 판정 중(/loading)을 거쳐도 남는다', () {
    final r = GateRedirector();

    expect(go(r, null, '/?error=access_denied'), GatePaths.loading);
    expect(go(r, const SignedOut(), GatePaths.loading), '/login?failed=1');
  });

  test('로그인 화면이 아닌 단계에서 본 ?error= 는 나중 로그인 화면에 실패 줄을 남기지 않는다', () {
    final r = GateRedirector();

    expect(go(r, const VerifyMfa('f'), '/?error=access_denied'), GatePaths.verify);
    // 2단계 입력에서 로그아웃 — 구글 로그인이 실패한 게 아니다
    expect(go(r, const SignedOut(), GatePaths.verify), GatePaths.login);
  });

  test('판정 중에 본 ?error= 도 로그인 밖 단계로 판정되면 버린다', () {
    final r = GateRedirector();

    expect(go(r, null, '/?error=access_denied'), GatePaths.loading);
    expect(go(r, const VerifyMfa('f'), GatePaths.loading), GatePaths.verify);
    expect(go(r, const SignedOut(), GatePaths.verify), GatePaths.login);
  });

  test('주소가 속한 메뉴: 정확히 같거나 그 아래, 홈은 / 하나만', () {
    expect(AdminSection.ownerOf('/reports'), AdminSection.reports);
    expect(AdminSection.ownerOf('/reports/123'), AdminSection.reports);
    expect(AdminSection.ownerOf('/'), AdminSection.home);
    expect(AdminSection.ownerOf('/reportsx'), isNull);
    expect(AdminSection.ownerOf('/login'), isNull);
  });
}
