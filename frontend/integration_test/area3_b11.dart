part of 'area3.dart';

// 영역 3 신뢰 확인 6개(E-CHAT-37 · 38 · 39 · 40 · 41 · 44)의 앱 쪽. PC 쪽은 e2e/area3_phone11.py 의 같은 번호.
//  - 37: 폰 계정이 방을 열고 `step('ready')` 에서 멈춘 사이 PC 가 상대로 수락한다 — 방 뷰모델이 수락 줄을 처음 가진 앱 시계(UTC)와 그려진 줄 글자를 말한다(area3_b8.dart 의 E-CHAT-10 과 같은 모양).
//  - 38 · 40 · 41: 앱은 홈에서 3초만 머문다(알림은 PC 가 알림창에서 읽는다) — E-ONB-61 과 같은 가설을 그대로 쓴다.
//  - 39 · 44: 두 기기(`번호/A` = 폰 · `번호/B` = 에뮬). support.step 은 이름만 말해 값을 못 싣고 두 기기 가설의 결과(pass)는 PC 가 못 읽으므로, 본 것은 `_trStep` 으로 실어 말한다
//    (`ready`/`armed` 는 PC 가 서로 맞추는 자리, `report` 가 끝에서 한 번). 수락을 누르는 길은 E-CHAT-43(_acceptTwice)과 같다 — 방금 만든 방의 배너 "수락하기" → 확인 창 "수락".
// 이 파일의 최상위 이름은 모두 `_tr` 로 시작한다(다른 묶음의 이름과 안 겹치게). 이 파일은 기기에서는 아직 안 돌려 봤다.

const _trAcceptKind = 'trust_accept'; // message.dart MessageKind.trustAccept.wire — 서버가 수락 줄에 붙이는 kind(chat/router.py:323)
const _trWait = Duration(minutes: 10); // 상대 기기를 기다리는 멈춤(support.step 기본은 2분)
const _trCardWait = Duration(seconds: 20); // 수락 뒤 14b 카드가 뜨기를 기다리는 상한

ProviderContainer _trContainer(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(ChatRoomScreen)));

String _trMatchId(WidgetTester tester) => tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).matchId;

/// 방 뷰모델이 방 읽기를 끝냈는가(최대 15초) — 읽기 전에 수락이 가면 수락 줄이 구독으로 안 온다. 오류가 있으면 못 끝낸 것이다.
Future<bool> _trLoaded(WidgetTester tester) async {
  final container = _trContainer(tester);
  final provider = chatRoomViewModelProvider(_trMatchId(tester));
  final watch = Stopwatch()..start();
  while (container.read(provider).isLoading && watch.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final state = container.read(provider);
  return !state.isLoading && state.errorMessage == null;
}

/// 두 기기 가설이 본 것을 PC 에 건네고 go 를 기다린다 — [data] 가 핸들러가 받는 말에 실린다(support.step 은 이름만 말한다).
Future<Map<String, dynamic>> _trStep(String name, Map<String, Object?> data) async {
  await say({'step': name, ...data});
  return hear(timeout: _trWait);
}

/// E-CHAT-37 — 방을 열고 읽기를 끝낸 뒤 `step('ready')` 에서 멈춘다. PC 가 그사이 상대로 수락하면 방 뷰모델이 그 줄을 처음 가진 앱 시계(UTC)와
/// 화면에 그려진 시스템 줄 글자를 말한다. 읽기를 못 끝내면 `step` 을 부르지 않고 `loaded: false` 로 끝낸다(PC 가 수락을 보내지 않는다).
Future<Map<String, Object?>> _trLiveLine(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final container = _trContainer(tester);
  final provider = chatRoomViewModelProvider(_trMatchId(tester));
  if (!await _trLoaded(tester)) {
    return {'loaded': false, 'error': container.read(provider).errorMessage, 'seen_at': null, 'lines': <String>[]};
  }
  String? seenAt;
  final sub = container.listen(provider, (_, next) {
    if (seenAt == null && next.messages.any((message) => message.kind.wire == _trAcceptKind)) {
      seenAt = DateTime.now().toUtc().toIso8601String();
    }
  });
  try {
    await wait(tester, const Duration(seconds: 2)); // 실시간 구독이 붙기 전에 수락이 오면 그 줄을 놓친다
    await step('ready'); // PC 가 A 로 수락한다
    final watch = Stopwatch()..start();
    while (seenAt == null && watch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500)); // 뷰모델이 줄을 가진 프레임엔 아직 안 그려졌을 수 있다
    final lines = [for (final line in tester.widgetList<SystemMessage>(find.byType(SystemMessage, skipOffstage: false))) line.body];
    return {'loaded': true, 'seen_at': seenAt, 'lines': lines};
  } finally {
    sub.close();
  }
}

/// 14b "신뢰 확인 완료" 카드가 뜰 때까지(최대 [_trCardWait]) 50ms 마다 본다 → 처음 보인 시각, 안 뜨면 null.
Future<DateTime?> _trCardAt(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < _trCardWait) {
    await tester.pump(const Duration(milliseconds: 50));
    if (_has(find.text(_batchTrustDone))) return DateTime.now();
  }
  return null;
}

/// 카드가 뜬 방에서 읽은 것 — 보이는 카카오톡 아이디(방 머리말의 값과 화면에 그려진 글자), 방 머리말의 사진 주소들, 앱바 머리 사진 주소.
/// 머리 사진은 통과하면 아바타에서 실사진으로 바뀐다(AnimatedSwitcher) — 바뀌는 동안은 둘이 겹치므로 1초 기다린 뒤 맨 위(마지막)를 읽는다.
Future<Map<String, Object?>> _trCardFacts(WidgetTester tester) async {
  await wait(tester, const Duration(seconds: 1));
  final room = _trContainer(tester).read(chatRoomViewModelProvider(_trMatchId(tester))).room;
  final kakao = room?.kakaoId;
  final avatars = find.descendant(of: find.byType(AppBar), matching: find.byType(CachedNetworkImage));
  return {
    'kakao_id': kakao,
    'kakao_shown': kakao != null && _has(find.descendant(of: find.byType(ChatRoomScreen), matching: find.text(kakao))),
    'photos': room?.photoUrls,
    'header_photo': avatars.evaluate().isEmpty ? null : tester.widgetList<CachedNetworkImage>(avatars).last.imageUrl,
  };
}

/// 방금 만든 방의 배너 "수락하기" → 확인 창 "수락" 이 떠서 자리를 잡은 뒤의 "수락" 버튼 — 누르지는 않는다(E-CHAT-43 과 같은 순서 · 기다림).
Future<Finder> _trOpenConfirm(WidgetTester tester) async {
  await pumpUntil(tester, button(_acceptBanner));
  await tap(tester, button(_acceptBanner));
  final confirm = find.widgetWithText(TextButton, _acceptConfirm);
  await pumpUntil(tester, confirm);
  await tester.pump(const Duration(milliseconds: 800)); // 창이 올라오는 동안은 버튼이 제자리가 아니다
  await tester.pump(const Duration(milliseconds: 800));
  return confirm;
}

/// E-CHAT-39 의 A — PC 가 미리 수락해 둔 방을 열어 기다림 배너를 단 채 `ready` 에서 선다. 상대(B)가 누르면 방 뷰모델이 상대 수락 줄을 받은 때 ·
/// 통과(gate.passed)를 읽은 때 · 카드가 그려진 때를 앱 시계로 재고(수락 줄 도착 → 카드 = `card_ms`), 카드가 뜨면 카카오톡 아이디 · 머리 사진을 읽는다.
Future<Map<String, Object?>> _trWatchPartner(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final container = _trContainer(tester);
  final provider = chatRoomViewModelProvider(_trMatchId(tester));
  final loaded = await _trLoaded(tester);
  DateTime? lineAt;
  DateTime? passedAt;
  final sub = container.listen(provider, (_, next) {
    final room = next.room;
    if (room == null) return;
    if (lineAt == null && next.messages.any((m) => m.kind.wire == _trAcceptKind && m.senderId == room.partner.profileId)) lineAt = DateTime.now();
    if (passedAt == null && room.gate.passed) passedAt = DateTime.now();
  });
  try {
    await wait(tester, const Duration(seconds: 2)); // 구독이 붙고 배너가 그려지는 시간
    await _trStep('ready', {'loaded': loaded, 'error': container.read(provider).errorMessage, 'banners': _banners(tester)});
    if (!loaded) return {'loaded': false, 'card': false};
    await _trStep('watch', {}); // PC 가 B 를 눌러도 되게 푼 뒤에야 풀린다 — 카드 기다림(20초)을 B 가 누르기 직전부터 센다
    final cardAt = await _trCardAt(tester);
    final line = lineAt;
    final passed = passedAt;
    return {
      'loaded': true,
      'card': cardAt != null,
      'card_ms': (line != null && cardAt != null) ? cardAt.difference(line).inMilliseconds : null,
      'passed_ms': (line != null && passed != null) ? passed.difference(line).inMilliseconds : null,
      ...await _trCardFacts(tester),
    };
  } finally {
    sub.close();
  }
}

/// E-CHAT-39 의 B · E-CHAT-44 의 A · B — 방을 열고 확인 창을 연 채 `armed` 에서 선다. PC 가 두 기기가 다 선 것을 보고 go 를 보내면 그때 "수락" 을 누르고,
/// 카드가 뜰 때까지 걸린 시간(`card_ms`, 누른 뒤)과 카드에서 읽은 것을 말한다. 방을 못 읽었으면 확인 창을 열지 않고 그것을 말한다(PC 가 blocked 로 끝낸다).
Future<Map<String, Object?>> _trPress(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final provider = chatRoomViewModelProvider(_trMatchId(tester));
  final loaded = await _trLoaded(tester);
  final confirm = loaded ? await _trOpenConfirm(tester) : null;
  await _trStep('armed', {'loaded': loaded, 'error': _trContainer(tester).read(provider).errorMessage, 'banners': _banners(tester)});
  if (confirm == null) return {'loaded': false, 'card': false};
  final pressedAt = DateTime.now();
  await tester.tap(confirm);
  final cardAt = await _trCardAt(tester);
  return {
    'loaded': true,
    'card': cardAt != null,
    'card_ms': cardAt?.difference(pressedAt).inMilliseconds,
    'error': _trContainer(tester).read(provider).errorMessage,
    ...await _trCardFacts(tester),
  };
}

/// [body] 가 본 것을 끝에서 `report` 로 PC 에 건넨다.
Area1Case _trReporting(Future<Map<String, Object?>> Function(WidgetTester tester, Map<String, dynamic> job) body) => _session((tester, job) async {
      await _trStep('report', await body(tester, job));
      return null;
    });

final Map<String, Area1Case> area3Cases11 = {
  'E-CHAT-37': _session(_trLiveLine),
  'E-CHAT-38': area1Cases['E-ONB-61']!,
  'E-CHAT-39/A': _trReporting(_trWatchPartner),
  'E-CHAT-39/B': _trReporting(_trPress),
  'E-CHAT-40': area1Cases['E-ONB-61']!,
  'E-CHAT-41': area1Cases['E-ONB-61']!,
  'E-CHAT-44/A': _trReporting(_trPress),
  'E-CHAT-44/B': _trReporting(_trPress),
};
