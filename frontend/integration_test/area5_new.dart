part of 'area5.dart';

// 영역 5 새 5개(묶음 area5-new — 폰 A: E-EDGE-12 · E-WD-19, B에뮬: E-EDGE-04 · E-WD-20 · E-EDGE-10). PC 쪽은 e2e/area5_new.py 의 같은 번호 —
// 계정 · DB 를 준비하고, 앱이 멈춘 사이 망(에뮬 지연 · 끊기 · 비행기 모드) · 세션(logout scope=global) · 시계 · 잠금을 바꾸고 판정한다.
// 앱은 화면을 열어 누르고 본 것을 Map 으로 말한다(문구는 사람이 읽는 글자 그대로, 못 본 것은 null). 이 파일의 이름은 모두 `_nw` 로 시작한다.
// 탈퇴 버튼은 area5_wd.dart 의 `_wdWithdraw` 로만 누르고, 거기 닿는 가설은 E-WD-19 · 20 둘이다(e2e/test_area5_new.py 가 고정).
// 다른 도우미(`_photo…` · `_act…` · `_ed…` · `_wd…`)는 같은 라이브러리의 것을 그대로 쓴다.
// 이 파일은 `flutter analyze` 만 통과했고 기기에서는 아직 안 돌려 봤다.

const _nwClockLoginWait = Duration(seconds: 75); // E-EDGE-10 시계를 넘긴 뒤 02 를 기다리는 한도 — 판정(60초)은 PC 가 한다
const _nwSlowLoginWait = Duration(seconds: 60); // E-WD-20 5초 지연 망에서 02 를 기다리는 한도

// ── E-EDGE-04 ───────────────────────────────────────────────────────────────────────────────────────

/// 15b "무료로 만들기" 를 누르자마자 답을 안 기다리는 말을 보내고(PC 가 1초 뒤 끊고 10초 뒤 켠다) 프레임마다 지켜본다 —
/// 변환 중 안내가 처음 보인 때 · 사라진 때(누른 뒤 ms), 15-3 실패 안내가 한 번이라도 떴는지, 끝에 새 그림이 됐는지.
Future<Map<String, Object?>> _nwRegenOffline(WidgetTester tester) async {
  // 망이 끊긴 사이 히어로가 새 그림을 받다 던지는 이미지 읽기 오류("Connection closed while receiving data")는 앱이 일부러 지켜보는 일이 아니다 —
  // 히어로(DecorationImage)는 오류 처리가 없어 실제 앱에서는 로그만 남고, 시험 바탕은 이것을 시험 실패로 바꿔 가설이 끝나 버린다. 세어 두고 흘려보낸다.
  var imageErrors = 0;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'image resource service') {
      imageErrors++;
      return;
    }
    previous?.call(details);
  };
  try {
    return {...await _nwRegenOfflineBody(tester), 'image_errors': imageErrors};
  } finally {
    FlutterError.onError = previous;
  }
}

Future<Map<String, Object?>> _nwRegenOfflineBody(WidgetTester tester) async {
  await _openMe(tester);
  final before = _avatarFile(tester);
  await _photoOpenSheet(tester);
  await step('ready'); // PC 가 망을 5초 늦춘다
  await _photoPress(tester, find.descendant(of: find.byType(SafetySheet), matching: find.text(_photoFreeCta)));
  final watch = Stopwatch()..start();
  await say({'step': 'pressed'}); // 답을 기다리지 않는다 — 기다리는 동안은 프레임이 멎어 안내를 못 본다
  var seen = false;
  var failed = false;
  int? endedMs;
  while (watch.elapsed < _photoWait) {
    await tester.pump(const Duration(milliseconds: 200));
    final up = _has(find.text(_photoGenerating));
    seen |= up;
    failed |= _has(find.text(_photoFailedToast));
    if (seen && !up && endedMs == null) endedMs = watch.elapsedMilliseconds;
    if (endedMs != null && _photoRegenState(tester) != 'generating') break;
  }
  await _actUntil(tester, () {
    failed |= _has(find.text(_photoFailedToast)); // 실패 안내는 상태가 바뀐 다음 프레임에 뜬다
    return _avatarFile(tester) != before;
  });
  return {
    'generating_seen': seen,
    'generating_ms': endedMs,
    'failed_toast': failed,
    'avatar_changed': _avatarFile(tester) != before,
    'regen_state': _photoRegenState(tester),
  };
}

// ── E-EDGE-10 ───────────────────────────────────────────────────────────────────────────────────────

/// 15-6 을 연 채 멈춤(PC 가 세션을 전부 끊음) → 키를 고쳐 저장 → 02 에 갔으면 알림을 읽고 끝. 15-5 로 저장됐으면 멈춤(PC 가 시계 +65분) →
/// 아무 탭(오늘) → 02 까지 ms 와 그때의 알림.
Future<Map<String, Object?>> _nwSessionCut(WidgetTester tester, Map<String, dynamic> job) async {
  await _openManage(tester);
  await _actEnterBasic(tester);
  await step('15-6:opened');
  await type(tester, _actHeightField, job['height'] as String);
  await wait(tester, const Duration(milliseconds: 400));
  FocusManager.instance.primaryFocus?.unfocus();
  await _edTapSave(tester);
  await _actUntil(tester, () => _has(screen('login')) || _title(tester) == _actManageTitle, timeout: const Duration(seconds: 30));
  if (_has(screen('login'))) {
    final (_, notice) = await _twoLoginNotice(tester);
    await step('end');
    return {'login_after_save': true, 'notice': notice, 'saved_title': null, 'login_ms': null, 'late_notice': null};
  }
  final savedTitle = _title(tester);
  await step('15-5:saved');
  final watch = Stopwatch()..start();
  await _returnTo(tester, '내 프로필');
  if (!_has(screen('login')) && _has(_tab('오늘'))) await tap(tester, _tab('오늘'));
  String? notice;
  while (watch.elapsed < _nwClockLoginWait && !_has(screen('login'))) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  final loginMs = _has(screen('login')) ? watch.elapsedMilliseconds : null;
  if (loginMs != null) notice = (await _twoLoginNotice(tester)).$2;
  await step('end');
  return {'login_after_save': false, 'notice': null, 'saved_title': savedTitle, 'login_ms': loginMs, 'late_notice': notice};
}

// ── E-EDGE-12 ───────────────────────────────────────────────────────────────────────────────────────

/// 넘침 오류가 가리키는 앱 코드 자리("relevant error-causing widget" 의 frontend/lib 파일:줄). 못 찾으면 오류 첫 줄.
String _nwWhere(FlutterErrorDetails details) {
  final text = details.toString();
  final at = RegExp(r'frontend/lib/([\w/]+\.dart):(\d+)').firstMatch(text) ?? RegExp(r'/lib/([\w/]+\.dart):(\d+)').firstMatch(text);
  return at == null ? details.exceptionAsString().split('\n').first : '${at.group(1)}:${at.group(2)}';
}

/// 지금 화면의 세로 목록을 모두 끝까지 내린다(목록은 보이는 줄만 만든다 — 끝까지 가야 아래 칸도 그려진다).
Future<void> _nwScrollToEnd(WidgetTester tester) async {
  for (final state in tester.stateList<ScrollableState>(find.byType(Scrollable)).toList()) {
    for (var i = 0; i < 10 && state.mounted && state.position.axis == Axis.vertical; i++) {
      if (state.position.pixels >= state.position.maxScrollExtent) break;
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// 나 탭 일곱 화면을 차례로 열어 끝까지 내리며 넘침 오류를 화면별로 모은다. 15-6 을 본 뒤 멈추면 PC 가 닉네임을 잠그고,
/// 앱이 내 프로필을 다시 읽어 15-6 을 다시 연다(15-6-2). 오류 처리기는 어떻게 끝나든 되돌린다.
Future<Map<String, Object?>> _nwOverflowWalk(WidgetTester tester, Map<String, dynamic> job) async {
  final found = <Map<String, Object?>>[];
  final visited = <String>[];
  var current = 'home';
  var locked = false;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) {
      found.add({'screen': current, 'where': _nwWhere(details)});
      return;
    }
    previous?.call(details);
  };
  Future<void> open(String name, Future<void> Function() go) async {
    current = name;
    await go();
    await _nwScrollToEnd(tester);
    visited.add(name);
  }

  double? scale;
  try {
    await arrive(tester, 'home');
    scale = MediaQuery.of(tester.element(find.byType(Scaffold).first)).textScaler.scale(8) / 8;
    final want = (job['scale'] as num).toDouble();
    if ((scale - want).abs() > 0.1) throw E2eBlocked('글자 배율 $scale 이 $want 가 아님 — 기기 설정이 안 먹었다');
    await open('15', () async {
      await tap(tester, _tab('나'));
      await pumpUntil(tester, find.byType(ProfileHero));
    });
    await open('15-4', () async {
      await tap(tester, _entry(_previewEntry));
      await pumpUntil(tester, find.byType(ProfileCard));
    });
    await _returnTo(tester, '내 프로필');
    await open('15-5', () async {
      await tap(tester, _entry(_manageEntry));
      await pumpUntil(tester, find.text(_sectionTitles.first));
    });
    await open('06-1', () => _actEnterIdeal(tester));
    await _returnTo(tester, _actManageTitle);
    await open('15-6', () => _actEnterBasic(tester));
    await _returnTo(tester, _actManageTitle);
    await step('lock'); // PC 가 nickname_changed_at 을 지금으로
    final container = ProviderScope.containerOf(tester.element(find.byType(ProfileManageScreen)));
    container.invalidate(myProfileProvider);
    await _actUntil(
      tester,
      () => container.read(myProfileProvider).value?.when(onSuccess: (p) => p.nicknameChangeableAt != null, onFailure: (_) => false) ?? false,
    );
    await open('15-6-2', () => _actEnterBasic(tester));
    locked = _has(find.byIcon(AppIcons.lock));
    await _returnTo(tester, _actManageTitle);
    await open('15-7', () => _photoOpenEditor(tester));
  } finally {
    FlutterError.onError = previous;
  }
  return {'overflows': found, 'visited': visited, 'locked': locked, 'scale_seen': scale};
}

// ── E-WD-19 · 20 ────────────────────────────────────────────────────────────────────────────────────

/// 최종 시트를 연 채 멈춤(PC 가 비행기 모드) → 누름 → 시트 안 문구 · 시트가 열린 채인지 · 02 로 갔는지 → 멈춤(PC 가 DB 를 보고 망을 되돌림) →
/// 다시 누르고 02 까지(E-WD-04 와 같다).
Future<Map<String, Object?>> _nwWithdrawOffline(WidgetTester tester) async {
  await _wdOpenFinal(tester);
  await step('final');
  await _wdWithdraw(tester);
  final error = find.descendant(of: find.byType(WithdrawFinalSheet), matching: find.text(_edNetwork));
  final seen = await appears(tester, error, const Duration(seconds: 20)) != null;
  final offline = {'error': seen ? _edNetwork : null, 'sheet_open': _has(find.byType(WithdrawFinalSheet)), 'login_seen': _has(screen('login'))};
  await step('failed');
  final tappedAt = await _wdWithdraw(tester);
  return {...offline, 'tapped_at': tappedAt, ...await _wdToLogin(tester)};
}

/// 최종 시트를 연 채 멈춤(PC 가 망을 5초 늦춤) → 누름 → 0.2초 뒤 버튼이 꺼졌는지 보고 한 번 더 누름 → 02 까지.
Future<Map<String, Object?>> _nwWithdrawTwice(WidgetTester tester) async {
  await _wdOpenFinal(tester);
  await step('final');
  final tappedAt = await _wdWithdraw(tester);
  await tester.pump(const Duration(milliseconds: 200));
  final button = find.descendant(of: find.byType(WithdrawFinalSheet), matching: find.byType(AppButton));
  final blocked = _has(button) && tester.widget<AppButton>(button.first).onPressed == null;
  await _wdWithdraw(tester); // 꺼진 버튼이면 아무 일도 없다
  return {'tapped_at': tappedAt, 'second_blocked': blocked, ...await _wdToLogin(tester, within: _nwSlowLoginWait)};
}

final Map<String, Area1Case> area5CasesNew = {
  'E-EDGE-04': _session((tester, job) => _nwRegenOffline(tester)),
  'E-EDGE-12': _session(_nwOverflowWalk),
  'E-WD-19': _session((tester, job) => _nwWithdrawOffline(tester)),
  'E-WD-20': _session((tester, job) => _nwWithdrawTwice(tester)),
  'E-EDGE-10': _session(_nwSessionCut),
};
