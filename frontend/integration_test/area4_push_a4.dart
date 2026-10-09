part of 'area4.dart';

// 영역 4 알림(PUSH) A4 — 토큰 · 권한 · 로그인/로그아웃(55 · 58~63 · 66~69). PC 쪽은 e2e/area4_push_a4.py 의 같은 번호.
// 알림을 보내고 읽고 권한 창을 누르는 일은 PC 가 한다(앱이 [step] 에서 멈춘 사이). 앱은 화면과 서버 응답 뒤의 상태만 본다.
// 이 묶음은 PC 가 멈춘 사이 알림을 최대 60초 기다리므로 PC 일이 있는 멈춤은 [_pcWork] 만큼 기다린다(기본 2분이면 모자란다).

const _pcWork = Duration(minutes: 6);
const _deviceOffNotice = '기기 알림이 꺼져 있어요. 알림을 받으려면 기기 설정에서 알림을 눌러 켜 주세요'; // notification_settings_screen.dart
const _deviceOffButton = '기기 알림 설정 열기';
const _reviewHeld = '조금 더 확인이 필요해요'; // 3b 대기 화면(status=pending) 제목 — area1_b3.dart 의 _held 와 같다

/// 알림 권한을 거부해도 앱은 그대로 쓴다 — 홈에 닿고 하단 탭이 보이고 "오늘" 탭을 누르면 오늘 화면이 열린다.
Future<void> _homeUsable(WidgetTester tester) async {
  await arrive(tester, 'home');
  must(find.byType(AppBottomNav).evaluate().isNotEmpty, '하단 내비가 안 보임');
  await tap(tester, _tab('오늘'));
  await wait(tester, const Duration(seconds: 2));
  must(find.byType(TodayCardsScreen).evaluate().isNotEmpty, '오늘 탭을 눌렀는데 오늘 화면이 안 열림');
}

/// 로그인한 뒤 PC 에게 넘기기 전에 프레임을 몇 초 돌린다 — 로그인만 하고 바로 멈추면 앱 위젯이 아직 한 프레임도 안 그려져
/// (스플래시 그대로) 알림 권한을 묻기 전이다. PC 가 "허용 안 함" 을 누르려 해도 누를 창이 없어 E-PUSH-59 · 60 · 62 가 blocked 가 됐다(10-06 실폰).
Future<void> _signedIn(WidgetTester tester) async {
  await wait(tester, const Duration(seconds: 5));
  await step('signed_in');
}

final Map<String, Area1Case> _pushA4Cases = {
  // 켬 → (PC 가 marketing · 동의 시각) → 끔 → (PC 가 false · null).
  'E-PUSH-55': _session((tester, job) async {
    const title = '혜택·이벤트 소식';
    await _open16d(tester);
    await _toTop(tester);
    await _reveal(tester, _tile(title));
    await tap(tester, _tile(title));
    await wait(tester, const Duration(seconds: 3)); // 서버 저장이 끝나기를
    must(_on(tester, title), '켰는데 스위치가 꺼져 있음');
    await step('on');
    await tap(tester, _tile(title));
    await wait(tester, const Duration(seconds: 3));
    must(!_on(tester, title), '껐는데 스위치가 켜져 있음');
    await step('off');
    return null;
  }),
  // 로그인해 홈에 닿고 멈춤 — PC 가 30초 안에 토큰 행이 올라오는지 본다.
  'E-PUSH-58': _session((tester, job) async {
    await arrive(tester, 'home');
    await step('home');
    return null;
  }),
  // 첫 실행(앱 데이터를 지운 상태)에서 로그인 → 권한 창이 뜬다 → 멈춘 사이 PC 가 "허용 안 함" → 앱은 그대로 홈.
  'E-PUSH-59': _session((tester, job) async {
    await _signedIn(tester);
    await _homeUsable(tester);
    return null;
  }),
  // phase=deny 는 59 와 같다. phase=again 은 PC 가 권한을 켠 뒤 앱을 껐다 다시 켠 것 — 저장된 세션으로 홈에 닿는다.
  'E-PUSH-60': _session((tester, job) async {
    if (job['phase'] == 'again') {
      await arrive(tester, 'home', timeout: const Duration(seconds: 30));
      must(screen('start').evaluate().isEmpty, '다시 켰는데 로그인 화면이 보임');
      return null;
    }
    await _signedIn(tester);
    await _homeUsable(tester);
    return null;
  }),
  // 권한이 이미 허용된 채 로그인해 홈에 닿는다 — 끄고 켜는 것과 알림 보내기는 PC 가 앱이 끝난 뒤에 한다.
  'E-PUSH-61': _session((tester, job) async {
    await arrive(tester, 'home');
    return null;
  }),
  // 거부한 사람이 16d 에 가면 맨 위 안내 상자 1개 + 버튼 1개 → 누르면 설정 앱 → (PC 가 켜고 앱을 앞으로) → 안내 상자가 사라진다.
  'E-PUSH-62': _session((tester, job) async {
    await _signedIn(tester);
    await _open16d(tester);
    await _toTop(tester);
    await pumpUntil(tester, find.text(_deviceOffNotice), timeout: const Duration(seconds: 10));
    must(find.text(_deviceOffNotice).evaluate().length == 1, '안내 상자가 1개가 아님');
    must(button(_deviceOffButton).evaluate().length == 1, '"$_deviceOffButton" 버튼이 1개가 아님');
    final noticeTop = tester.getTopLeft(find.text(_deviceOffNotice)).dy;
    final firstSwitchTop = tester.getTopLeft(find.text('오늘의 카드 도착')).dy;
    must(noticeTop < firstSwitchTop, '안내 상자가 스위치보다 위가 아님');
    // 누르면 설정 앱이 앞으로 와서 이 앱의 프레임이 멈춘다 — pump 로 기다리면 PC 가 부르기 전에 걸린다. 누르고 바로 멈춰 PC 에게 넘긴다.
    await tester.tap(button(_deviceOffButton).last);
    await step('opened');
    final watch = Stopwatch()..start();
    while (find.text(_deviceOffNotice).evaluate().isNotEmpty) {
      must(watch.elapsed < const Duration(seconds: 15), '알림을 켜고 앱으로 돌아왔는데 15초 안에 안내 상자가 안 사라짐');
      await tester.pump(const Duration(milliseconds: 200));
    }
    return {'note': '돌아온 뒤 안내 상자가 ${watch.elapsedMilliseconds}ms 만에 사라짐'};
  }),
  // 인증 전 계정(대기 화면)에서 멈춤 → PC 가 토큰 행 확인 · 통과 처리 → 3c(30초 폴링) → 학과 · 학번을 저장해 게이트가 열림(04-1) →
  // 멈춤 → PC 가 같은 토큰 1행인지(게이트가 열릴 때 등록을 다시 부르는 길 — main.dart `_startPushWhenGateOpens`).
  'E-PUSH-63': _session((tester, job) async {
    await pumpUntil(tester, find.text(_reviewHeld), timeout: const Duration(seconds: 30));
    await step('waiting');
    final took = await appears(tester, screen('3c'), const Duration(seconds: 40));
    must(took != null, '통과 처리 뒤 40초 안에 3c 로 안 넘어감');
    await type(tester, input('예: 컴퓨터공학과'), '컴퓨터공학과');
    await type(tester, input('예: 21'), '21');
    await tap(tester, button('다음'));
    await arrive(tester, '04-1', timeout: const Duration(seconds: 10));
    await step('gate_open');
    return {'note': '통과 처리 뒤 3c 까지 ${took!.inMilliseconds}ms'};
  }),
  // 로그인 중(PC 가 알림이 오는지 봄) → 로그아웃 → 로그인 화면.
  'E-PUSH-66': _session((tester, job) async {
    await _openSettings(tester);
    await step('logged_in', timeout: _pcWork);
    await _confirmLogout(tester);
    await arrive(tester, 'start', timeout: const Duration(seconds: 15));
    return null;
  }),
  // A 로그인(PC 가 토큰 행) → 로그아웃 → C 로그인 → (PC 가 토큰 주인 · 두 알림).
  'E-PUSH-67': _session((tester, job) async {
    await _openSettings(tester);
    await step('first_ready');
    await _confirmLogout(tester);
    await arrive(tester, 'start', timeout: const Duration(seconds: 15));
    await signIn(job['second'] as String);
    await arrive(tester, 'home', timeout: const Duration(seconds: 40));
    await step('second_ready', timeout: _pcWork);
    return null;
  }),
  // 설정에서 멈춤(PC 가 알림 확인 · 비행기 모드 켬) → 로그아웃(망 없음) → 로그인 화면 · 오류 문구 0 → 멈춤(PC 가 망을 켜고 1분 넘게 기다린 뒤 알림).
  'E-PUSH-68': _session((tester, job) async {
    await _openSettings(tester);
    await step('logged_in', timeout: _pcWork);
    await _confirmLogout(tester);
    await arrive(tester, 'start', timeout: const Duration(seconds: 30));
    must(find.text(const UnknownFailure().toDisplayMessage()).evaluate().isEmpty, '오류 문구가 보임');
    await step('logged_out', timeout: _pcWork);
    return null;
  }),
  // 로그인해 홈에 닿는다 — 가짜 토큰 넣기와 알림 보내기는 PC 가 앱이 끝난 뒤에 한다.
  'E-PUSH-69': _session((tester, job) async {
    await arrive(tester, 'home');
    return null;
  }),
};
