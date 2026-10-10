part of 'area5.dart';

// 영역 5 폰 A 한 대 · 탈퇴 흐름(묶음 area5-wd — E-WD-12 는 앱이 없는 API 가설). PC 쪽은 e2e/area5_wd.py 의 같은 번호 — 계정 · DB 를 준비하고 판정한다.
// 앱은 화면을 열어 누르고 본 것을 Map 으로 말한다(문구는 사람이 읽는 글자 그대로, 못 본 것은 null).
// 탈퇴 버튼("정말 영구 삭제")은 [_wdWithdraw] 한 곳에서만 누르고, 거기 닿는 가설은 E-WD-04 · 16 · 18 · E-EDGE-20 넷이다(e2e/test_area5_wd.py 가 고정).
// 누르기는 줄 전체 폭 위젯의 가운데가 아니라 안의 글자를 누른다(#282). 시트 안 버튼은 시트가 다 올라온 뒤(_openFinalSheet 가 기다린다) 누른다.
// 소셜 로그인 전환 뒤 아래 "02(로그인 화면)" 은 로그아웃하면 닿는 시작 화면(screen('start'))이다 — 02 는 로그인한 계정의 학교 메일 인증 화면이 됐다.

const _wdForever = '정말 영구 삭제'; // withdraw_sheets.dart 최종 시트 AppButton
const _wdPause = '일시중지'; // withdraw_sheets.dart `_PauseOffer` TextButton
const _wdMatching = '매칭 활성화'; // settings_screen.dart SwitchListTile
const _wdRequestCode = '인증 메일 받기'; // sign_up_screen.dart AppButton
const _wdEmailHint = 'hong@snu.ac.kr'; // sign_up_screen.dart 이메일 칸 힌트
const _wdLoginWait = Duration(seconds: 20); // 02 를 기다리는 한도 — 시간 판정은 PC 가 한다

/// 지금 떠 있는 토스트 글자(없으면 null) — 02 의 알림은 AppToast 다(sign_up_screen.dart).
String? _wdToast(WidgetTester tester) {
  final toasts = find.byType(AppToast);
  return _has(toasts) ? tester.widget<AppToast>(toasts.first).label : null;
}

/// 나 탭 → 설정 → "탈퇴하기" → 1차 시트 "영구 삭제" → 최종 시트까지(area5.dart 도우미).
Future<void> _wdOpenFinal(WidgetTester tester) async {
  await _openMe(tester);
  await _openSettings(tester);
  await _openWithdrawSheet(tester);
  await _openFinalSheet(tester);
}

/// 최종 시트의 "정말 영구 삭제" 글자를 누르고 누른 시각(UTC)을 돌려준다 — 이 파일에서 탈퇴 버튼을 누르는 곳은 여기 하나다.
/// 시트가 이미 닫혔으면(앱이 정지 · 로그아웃을 먼저 알아챔) PC 가 만든 경합이 깨진 것이라 blocked.
Future<String> _wdWithdraw(WidgetTester tester) async {
  final label = find.descendant(of: find.byType(WithdrawFinalSheet), matching: find.text(_wdForever));
  if (!_has(label)) throw E2eBlocked('누르기 전에 최종 시트가 닫힘 — 지금 화면 ${_title(tester)}');
  await tester.ensureVisible(label);
  await tester.pump();
  final at = DateTime.now().toUtc().toIso8601String();
  await tester.tap(label);
  return at;
}

/// 누른 뒤 02(로그인 화면)가 처음 그려질 때까지 걸린 ms 와 그때의 알림 글자. [within] 안에 못 닿으면 둘 다 null(느린 망은 늘린다 — E-WD-20).
Future<Map<String, Object?>> _wdToLogin(WidgetTester tester, {Duration within = _wdLoginWait}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < within) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_has(screen('start'))) {
      final ms = watch.elapsedMilliseconds;
      // 알림은 시작 화면의 첫 프레임 뒤(addPostFrameCallback)에 뜬다 — 첫 프레임에 읽으면 늘 null 이다.
      final shown = await appears(tester, find.byType(AppToast), const Duration(milliseconds: 1500));
      return {'login_ms': ms, 'notice': shown == null ? null : _wdToast(tester)};
    }
  }
  return {'login_ms': null, 'notice': null};
}

/// 02 에 다시 들어간다 — 로그아웃 상태에서 한 번 더 로그아웃하면 SessionScope 가 화면 트리를 새로 만든다(로그아웃 뒤 02 가 처음 그려지는 길과 같다).
/// 새 02 가 그려지면 1.5초 동안 알림이 다시 뜨는지 본다.
Future<Map<String, Object?>> _wdReenter(WidgetTester tester) async {
  final before = screen('start').evaluate().first;
  await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  final watch = Stopwatch()..start();
  var fresh = false;
  while (!fresh && watch.elapsed < const Duration(seconds: 10)) {
    await tester.pump(const Duration(milliseconds: 100));
    final seen = screen('start').evaluate();
    fresh = seen.isNotEmpty && !identical(seen.first, before);
  }
  String? again;
  final look = Stopwatch()..start();
  while (fresh && again == null && look.elapsed < const Duration(milliseconds: 1500)) {
    await tester.pump(const Duration(milliseconds: 100));
    again = _wdToast(tester);
  }
  return {'reentered': fresh, 'notice_again': again};
}

/// 설정 맨 위 "매칭 활성화" 토글 값 — 탈퇴하기까지 내려간 목록을 맨 위로 되돌려 읽는다(목록은 보이는 줄만 만든다). 5초 안에 못 찾으면 null.
Future<bool?> _wdMatchingToggle(WidgetTester tester) async {
  final settings = find.ancestor(of: screen('settings'), matching: find.byType(Scaffold)).first;
  tester.state<ScrollableState>(find.descendant(of: settings, matching: find.byType(Scrollable)).first).position.jumpTo(0);
  final toggle = find.widgetWithText(SwitchListTile, _wdMatching);
  if (await appears(tester, toggle, const Duration(seconds: 5)) == null) return null;
  return tester.widget<SwitchListTile>(toggle).value;
}

/// 02 에 [email] 을 넣고 "인증 메일 받기" 글자를 누른 뒤 15초 안에 03(코드 화면)이 뜨는지 · 칸 아래 빨간 글자(거절 문구)가 뜨는지.
/// 소셜 로그인 전환 뒤 02 는 로그인한 계정의 학교 메일 인증 관문이다 — 학교 메일 인증 전 계정으로 로그인해 와야 닿는다.
Future<Map<String, Object?>> _wdAskCode(WidgetTester tester, String email) async {
  await arrive(tester, 'schoolEmail');
  await type(tester, input(_wdEmailHint), email);
  await tap(tester, find.descendant(of: find.byType(AppButton), matching: find.text(_wdRequestCode)));
  final error = find.byWidgetPredicate((w) => w is Text && w.style?.color == AppColors.error);
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 15) && !_has(screen('code')) && !_has(error)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return {'code_screen': _has(screen('code')), 'error': _textOf(tester, error)};
}

/// E-WD-14 · 15(탈퇴한 메일로 02 에서 다시 가입) — 소셜 로그인 전환으로 막아 둔다(PC 쪽 e2e/area5_wd.py REJOIN_ON_02_BLOCKED 와 같은 까닭).
/// 옛 PC 흐름은 로그아웃 상태로 켠다(02 에 못 닿는다). 대체 가설이 생겨 PC 가 02 로 보내는 계정(학교 메일 인증 전)으로
/// 로그인시켜 오면 [_wdAskCode] 판정을 그대로 쓴다.
Future<Map<String, Object?>> _wdRejoinOn02(WidgetTester tester, Map<String, dynamic> job) async {
  if (Supabase.instance.client.auth.currentSession == null) {
    throw E2eBlocked('소셜 로그인 전환으로 의미 변경, 대체 가설 필요 — 02 는 로그인한 계정의 학교 메일 인증이고, '
        '시험 계정의 학교 메일 해시가 임의값이라 같은 메일 재가입 거절을 확인할 수 없음');
  }
  return _wdAskCode(tester, job['email'] as String);
}

/// 최종 시트를 연 채 `final` 에서 멈췄다가(PC 가 정지를 걸거나 먼저 탈퇴한다) "정말 영구 삭제" 를 누르고 02 까지.
/// 멈추기 전에 연 시트가 일반 최종 시트("정말 삭제할까요?")였는지도 말한다 — 앱은 PC 가 바꾼 상태를 모른다.
Future<Map<String, Object?>> _wdRace(WidgetTester tester) async {
  await _wdOpenFinal(tester);
  final normal = _has(find.text(_finalTitle));
  await step('final');
  final tappedAt = await _wdWithdraw(tester);
  return {'tapped_at': tappedAt, 'normal_sheet': normal, ...await _wdToLogin(tester)};
}

/// E-EDGE-20 첫 켬 — "정말 영구 삭제" 를 누르자마자 답(go)을 기다리지 않는 멈춤 말을 보낸다. PC 가 0.3초를 채워 이 프로세스를 죽인다.
/// 죽지 않으면 30초 뒤 끝난다(PC 는 그때 이미 blocked 로 끝냈다).
Future<Map<String, Object?>?> _wdPressThenDie(WidgetTester tester, Map<String, dynamic> job) async {
  await _wdOpenFinal(tester);
  await _wdWithdraw(tester);
  await say({'step': 'pressed'});
  await wait(tester, const Duration(seconds: 30));
  return null;
}

/// E-EDGE-20 다시 켬(저장된 세션 그대로 — 로그아웃 · 새 로그인을 안 한다). 30초 안에 홈이나 02 에 닿으면 3초 더 지켜본다.
/// 그동안 홈 · 02 가 한 번이라도 보였는지와 02 의 알림 글자.
Future<Map<String, Object?>> _wdAfterRestart(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  Duration? landed;
  var home = false;
  var login = false;
  String? notice;
  while (watch.elapsed < const Duration(seconds: 30) && (landed == null || watch.elapsed - landed < const Duration(seconds: 3))) {
    await tester.pump(const Duration(milliseconds: 100));
    home |= _has(screen('home')) || _has(find.byType(AppBottomNav));
    if (_has(screen('start'))) {
      login = true;
      notice ??= _wdToast(tester);
    }
    if ((home || login) && landed == null) landed = watch.elapsed;
  }
  return {'home_seen': home, 'login_seen': login, 'notice': notice};
}

final Map<String, Area1Case> area5CasesWd = {
  'E-WD-02': _session((tester, job) async {
    await _openMe(tester);
    await _openSettings(tester);
    await _openWithdrawSheet(tester);
    await tap(tester, find.descendant(of: find.byType(WithdrawFirstSheet), matching: find.text(_wdPause)));
    await wait(tester, const Duration(seconds: 1)); // 시트가 닫히는 움직임
    final closed = !_has(find.text(_firstTitle));
    return {'sheet_closed': closed, 'toggle_on': await _wdMatchingToggle(tester)};
  }),
  'E-WD-04': _session((tester, job) async {
    await _wdOpenFinal(tester);
    final tappedAt = await _wdWithdraw(tester);
    final login = await _wdToLogin(tester);
    if (login['login_ms'] == null) {
      return {'tapped_at': tappedAt, ...login, 'notice_gone': false, 'reentered': false, 'notice_again': null};
    }
    await wait(tester, const Duration(milliseconds: 3500)); // 알림은 3초 뒤 사라진다(sign_up_screen.dart)
    final gone = _wdToast(tester) == null;
    return {'tapped_at': tappedAt, ...login, 'notice_gone': gone, ...await _wdReenter(tester)};
  }),
  // 탈퇴한 계정(auth 사용자는 남음)으로 새로 로그인 — 알림이 뜰 때까지 프레임마다 홈이 그려졌는지 본다.
  // 로그인 직전에도 로그인 화면이 잠깐 보이므로(앞 세션을 지움) 02 가 아니라 알림이 뜬 것을 끝으로 잰다(E-AUTH-09 와 같다).
  'E-WD-13': _session((tester, job) async {
    final watch = Stopwatch()..start();
    var home = false;
    String? notice;
    while (notice == null && watch.elapsed < _wdLoginWait) {
      await tester.pump(const Duration(milliseconds: 100));
      home |= _has(screen('home')) || _has(find.byType(AppBottomNav));
      if (_has(screen('start'))) notice = _wdToast(tester);
    }
    return {'notice': notice, 'login_seen': _has(screen('start')), 'home_seen': home, 'notice_ms': watch.elapsedMilliseconds};
  }),
  'E-WD-14': _session((tester, job) => _wdRejoinOn02(tester, job)),
  'E-WD-15': _session((tester, job) => _wdRejoinOn02(tester, job)),
  'E-WD-16': _session((tester, job) => _wdRace(tester)),
  'E-WD-18': _session((tester, job) => _wdRace(tester)),
  'E-EDGE-20': (tester, job) => job['phase'] == 'after' ? _wdAfterRestart(tester) : _session(_wdPressThenDie)(tester, job),
};
