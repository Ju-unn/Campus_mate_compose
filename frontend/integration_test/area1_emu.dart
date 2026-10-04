part of 'area1.dart';

// 영역 1 B에뮬 가설 — 네트워크를 끊고 · 시계를 앞당기고 · 브라우저를 끄는 것은 실폰에 못 해서 에뮬에서만 돈다.
// PC 쪽은 e2e/area1_emu.py 의 같은 번호 — 끊고 켜는 일은 PC 가 하고, 앱은 멈춰 서서(step) 기다린다.

const _networkDown = '네트워크 연결을 확인해 주세요'; // NetworkFailure
const _browserFailed = '알 수 없는 오류가 발생했습니다'; // 02-c _view 의 UnknownFailure
const _offlineHint = '연결되면 하던 곳으로 돌아갈게요';

/// 01-1 을 기다리는 동안 02-c · 04-1 이 한 번이라도 보였는지 — 인터넷이 없을 땐 이 둘로 새면 안 된다.
bool _leaked() => screen('consent').evaluate().isNotEmpty || screen('04-1').evaluate().isNotEmpty;

/// [name] 이 [within] 안에 나타나는 동안 02-c · 04-1 이 보였는지 함께 본다 → (나타났는지, 샜는지).
Future<(bool, bool)> _arriveWatching(WidgetTester tester, String name, Duration within) async {
  final watch = Stopwatch()..start();
  var leaked = false;
  while (watch.elapsed < within) {
    await tester.pump(const Duration(milliseconds: 100));
    leaked |= _leaked();
    if (screen(name).evaluate().isNotEmpty) return (true, leaked);
  }
  return (false, leaked);
}

/// 3b 제출 폼이 안 나오면 지금 어느 화면인지를 알려 준다(에뮬 첫 실행 E-GATE-47: 30초 동안 폼이 안 나왔는데 이유를 몰랐다).
/// 버튼 종류 · 스크롤 문제가 아니다 — 폼의 AppButton 은 스크롤 영역 밖 하단에 고정이라 폼이 있으면 늘 트리에 있다.
Future<void> _proofFormOrWhere(WidgetTester tester) async {
  if (await appears(tester, _proofForm, const Duration(seconds: 30)) != null) return;
  throw TestFailure('30초 안에 3b 제출 폼이 안 나옴 — 지금 보이는 것: ${_whereNow()}');
}

final Map<String, Area1Case> _emuCases = {
  // 로그인 → (PC 가 네트워크를 끔) 끈 채 켬 → 01-1 → 켜고 "다시 시도" → 홈 → (따로) 다시 실행해도 홈.
  'E-AUTH-22': _session((tester, job) async {
    switch (job['phase']) {
      case 'login':
        await arrive(tester, 'home');
        return null;
      case 'offline':
        final (shown, leakedFirst) = await _arriveWatching(tester, '01-1', const Duration(seconds: 30));
        must(shown, '네트워크 없이 켰는데 30초 안에 01-1 인터넷 없음 화면이 안 나옴');
        must(!leakedFirst, '01-1 이 뜨기 전에 02-c · 04-1 이 보임');
        must(find.text(_offlineHint).evaluate().isNotEmpty, '설명 "$_offlineHint" 없음');
        // 끈 채 "다시 시도" 는 01-1 그대로, 토스트 없음.
        await tap(tester, button('다시 시도'));
        await wait(tester, const Duration(seconds: 4));
        must(screen('01-1').evaluate().isNotEmpty, '끈 채 다시 시도했더니 01-1 을 벗어남');
        must(find.byType(AppToast).evaluate().isEmpty, '끈 채 다시 시도했더니 토스트가 뜸');
        must(!_leaked(), '끈 채 다시 시도했더니 02-c · 04-1 이 보임');
        await step('online'); // PC 가 네트워크를 켜고 닿을 때까지 기다린다
        await tap(tester, button('다시 시도'));
        final watch = Stopwatch()..start();
        final (home, leaked) = await _arriveWatching(tester, 'home', const Duration(seconds: 5));
        must(home, '네트워크를 켜고 다시 시도했는데 5초 안에 홈이 안 나옴');
        must(!leaked, '홈으로 가는 동안 02-c · 04-1 이 보임');
        return {'note': '다시 시도 → 홈 ${watch.elapsedMilliseconds}ms'};
      default:
        return _arriveAt(tester, job); // 강제 종료 → 실행도 5초 안에 홈, 로그인 화면 0번
    }
  }),
  // 로그인 → (PC 가 에뮬 시계를 +2시간) 다시 열기 → 로그인 화면 0번, 홈 API 가 값을 받음.
  'E-AUTH-19': _session((tester, job) async {
    if (job['phase'] == 'login') {
      await arrive(tester, 'home');
      return null;
    }
    await _arriveAt(tester, job);
    // 세션 만료 시각(expiresAt)은 서버 시계로 와서 +2시간 시계에선 늘 지난 것으로 읽힌다 — 판정은 홈 API 가 값을 받았는지로 한다.
    final container = ProviderScope.containerOf(tester.element(screen('home')));
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 15)) {
      final summary = container.read(homeSummaryProvider);
      // 이 provider 는 API 가 실패해도 던지지 않고 null 을 돌려준다(home_summary_provider.dart) — 값이 있어야 200 이다.
      if (summary.value != null) return {'note': '홈 요약 ${watch.elapsedMilliseconds}ms'};
      if (summary.hasValue) {
        must(watch.elapsed < const Duration(seconds: 5), '홈 요약이 null — 홈 API 가 200 을 못 받음');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    throw TestFailure('15초 안에 홈 요약이 안 옴');
  }),
  // 브라우저가 없는 기기에서 "보기" → 버튼 위 토스트 1개가 3초 뒤 사라진다.
  'E-GATE-12': _session((tester, job) async {
    await arrive(tester, 'consent');
    final view = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '이용약관 보기');
    await tester.ensureVisible(view);
    await tester.pump();
    await tester.tap(view);
    final toast = find.text(_browserFailed);
    final shown = await appears(tester, toast, const Duration(seconds: 2));
    must(shown != null, '"보기" 를 눌렀는데 2초 안에 토스트 "$_browserFailed" 가 안 뜸');
    must(toast.evaluate().length == 1, '토스트가 ${toast.evaluate().length}개');
    must(tester.getTopLeft(toast).dy < tester.getTopLeft(button(_consentCta).last).dy, '토스트가 동의 버튼 위가 아님');
    // 토스트가 뜬 때부터 센다 — 탭부터 뜰 때까지([shown])는 수명이 아니다(처음엔 이 둘을 더해 5.6초로 잘못 쟀다, 10-05).
    final watch = Stopwatch()..start();
    var slowest = Duration.zero; // 프레임 하나가 오래 걸린 만큼 "사라짐" 을 늦게 본다 — 에뮬의 소프트웨어 렌더링 탓인지 가르는 값
    var last = Duration.zero;
    while (toast.evaluate().isNotEmpty && watch.elapsed < const Duration(seconds: 8)) {
      await tester.pump(const Duration(milliseconds: 100));
      final now = watch.elapsed;
      if (now - last > slowest) slowest = now - last;
      last = now;
    }
    must(toast.evaluate().isEmpty, '8초가 지나도 토스트가 안 사라짐');
    final held = watch.elapsed;
    final detail = '토스트 ${held.inMilliseconds}ms(뜨기까지 ${shown!.inMilliseconds}ms · 확인 간격 최대 ${slowest.inMilliseconds}ms)';
    // 앱 타이머는 3초(consent_screen.dart _showNotice) — 확인 간격만큼 늦게 보이는 것은 허용하되 그 이상이면 앱 쪽을 의심한다.
    // watch 는 "토스트가 처음 보인 때" 가 아니라 "appears 가 알린 때" 에 시작한다 — 알리기 직전 프레임이 느렸으면 그만큼 짧게 잰다.
    must(held + slowest >= const Duration(milliseconds: 2500), '토스트가 너무 빨리 사라짐: $detail');
    must(held <= const Duration(milliseconds: 3200) + slowest, '토스트가 3초보다 오래 떠 있음: $detail');
    must(screen('consent').evaluate().isNotEmpty, '토스트 뒤 02-c 를 벗어남');
    return {'note': detail};
  }),
  // 사진 · 실명을 다 넣고 멈춤 → PC 가 네트워크를 끊음 → 제출 → 문구가 뜨고 버튼이 다시 켜진다(스피너 굳음 0).
  'E-GATE-47': _session((tester, job) async {
    await _proofFormOrWhere(tester);
    final container = await _fillProof(tester, job);
    await step('filled');
    await tap(tester, _proofForm);
    final watch = Stopwatch()..start();
    String? outcome;
    while (watch.elapsed < const Duration(seconds: 40) && outcome == null) {
      if (screen('3c').evaluate().isNotEmpty) outcome = '3c';
      if (find.text(_held).evaluate().isNotEmpty) outcome = 'held';
      final state = container.read(studentVerificationViewModelProvider);
      if (!state.isSubmitting && state.errorMessage != null) outcome = state.errorMessage;
      if (outcome == null) await tester.pump(const Duration(milliseconds: 100));
    }
    must(outcome != null, '제출 뒤 40초 안에 결과가 안 나옴(스피너가 굳음)');
    _faceFound(outcome!, job);
    must(outcome == _networkDown, '네트워크가 끊겼는데 결과가 "$outcome"');
    await tester.pump();
    must(find.text(_networkDown).evaluate().isNotEmpty, '상태엔 문구가 있는데 화면에 안 그려짐');
    must(!container.read(studentVerificationViewModelProvider).isSubmitting, '문구는 떴는데 제출 중 상태가 남음');
    must(enabled(tester, _submitProof), '문구는 떴는데 "$_submitProof" 버튼이 다시 안 켜짐');
    return {'note': '문구까지 ${watch.elapsedMilliseconds}ms'};
  }),
};
