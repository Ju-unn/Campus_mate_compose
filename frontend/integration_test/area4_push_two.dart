part of 'area4.dart';

// 영역 4 알림(PUSH) 두 기기 — E-PUSH-64 · 65 · 71. 열쇠는 `번호/A`(폰) · `번호/B`(에뮬)이고 PC 쪽은 e2e/area4_push_two.py 의 같은 번호.
// 두 기기가 같은 계정으로 로그인한다. 1회용 토큰은 같은 계정이 새로 받으면 앞 것이 죽으므로 B 는 로그아웃한 채 멈춰 있다가
// A 가 로그인한 뒤 PC 가 go 에 실어 준 새 토큰으로 로그인한다. 알림을 보내고 읽는 것은 PC 가 한다.
// 이 파일은 `flutter analyze` 만 돌렸고 기기에서는 아직 안 돌려 봤다.

const _peerWait = Duration(minutes: 10); // 상대 기기와 PC 가 일을 끝내기를 기다리는 멈춤

/// B: 로그아웃한 채 [name] 에서 멈춘다 — PC 가 A 의 로그인을 확인한 뒤 go 에 새 토큰을 실어 주면 로그인해 홈에 닿는다.
Future<void> _joinAfter(WidgetTester tester, String name) async {
  await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  final go = await step(name, timeout: _peerWait);
  await signIn(go['token_hash'] as String);
  await arrive(tester, 'home', timeout: const Duration(seconds: 40));
}

final Map<String, Area1Case> _pushTwoCases = {
  // A 가 홈에서 멈춤(PC 가 A 토큰 행) → B 가 로그인해 홈에서 멈춤(PC 가 토큰 2행 · 알림을 두 기기에서 읽음) → A 는 그 끝까지 기다린다.
  'E-PUSH-64/A': _session((tester, job) async {
    await arrive(tester, 'home');
    await step('in');
    await step('hold', timeout: _peerWait);
    return null;
  }),
  'E-PUSH-64/B': _session((tester, job) async {
    await _joinAfter(tester, 'wait');
    await step('in', timeout: _peerWait);
    return null;
  }),
  // 64 상태에서 A 가 설정 → 로그아웃 → 로그인 화면. B 는 그동안 로그인한 채 홈에 있고, 끝까지 로그인 화면으로 안 돌아간다.
  'E-PUSH-65/A': _session((tester, job) async {
    await _openSettings(tester);
    await step('in');
    await step('both', timeout: _peerWait);
    await _confirmLogout(tester);
    await arrive(tester, 'start', timeout: const Duration(seconds: 15));
    await step('out', timeout: _peerWait);
    return null;
  }),
  'E-PUSH-65/B': _session((tester, job) async {
    await _joinAfter(tester, 'wait');
    await step('in', timeout: _peerWait);
    await step('stay', timeout: _peerWait);
    must(screen('start').evaluate().isEmpty, 'A 가 로그아웃했는데 B 가 로그인 화면으로 돌아감 — 로그아웃은 그 기기만이어야 함');
    must(find.byType(AppBottomNav).evaluate().isNotEmpty, 'A 가 로그아웃한 뒤 B 의 하단 내비가 안 보임');
    return null;
  }),
  // A 가 설정 → 탈퇴하기 → 영구 삭제 → 정말 영구 삭제 → 로그인 화면. B 는 그 뒤에 세션을 강제로 새로 받으려 해 로그인 화면으로 돌아간다
  // (스스로 알아채는 데 최대 1시간 걸리는 것이 알려진 한계라 새로고침을 앞당긴다).
  'E-PUSH-71/A': _session((tester, job) async {
    await _openSettings(tester);
    await step('in');
    await step('both', timeout: _peerWait);
    await _settingsButton(tester, '탈퇴하기');
    await pumpUntil(tester, find.text('정말 떠나시나요?'), timeout: const Duration(seconds: 5));
    await tap(tester, button('영구 삭제'));
    await pumpUntil(tester, find.text('정말 삭제할까요?'), timeout: const Duration(seconds: 5));
    await tap(tester, button('정말 영구 삭제'));
    await arrive(tester, 'start', timeout: const Duration(seconds: 15));
    await step('withdrawn', timeout: _peerWait);
    return null;
  }),
  'E-PUSH-71/B': _session((tester, job) async {
    await _joinAfter(tester, 'wait');
    await step('in', timeout: _peerWait);
    await step('stay', timeout: _peerWait);
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {} // 지워진 계정이라 새로고침은 실패한다 — 화면이 로그인으로 돌아가는지가 판정
    await arrive(tester, 'start', timeout: const Duration(seconds: 30));
    return null;
  }),
};
