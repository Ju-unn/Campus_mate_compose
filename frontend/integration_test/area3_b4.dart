part of 'area3.dart';

// 영역 3 폰 A 한 대 4차 — 매칭 시각을 과거로 옮긴 방의 14f 신뢰 확인 시트 6개(E-CHAT-45 · 46 · 47 · 48 · 49 · 56). PC 쪽은 e2e/area3_phone4.py 의
// 같은 번호(계정 · 매칭을 만들고 DB 의 matches.created_at 만 옮긴 뒤 앱을 켠다. 아이디 · 나가기 · 수락 줄은 DB 에서 센다). 앱은 방을 열어 화면에서 본
// 것을 Map 으로 돌려주고 판정은 PC 가 한다. 시간은 PC 가 옮긴 DB 시각뿐이다 — 폰 시계는 건드리지 않는다.
// 화면 글자 · 위젯은 시나리오가 아니라 지금 화면 코드(chat_room_screen · trust_gate_sheet · chat_dialogs · kakao_id_settings_screen · chat_errors)에서 옮겼다.
// 시트는 방을 열 때마다(`_maybeShowSheet`) 방 상태가 바뀔 때 뜨고, 24시간 경계는 방을 읽은 순간 걸리는 Timer(`_scheduleReminder`)가 맞춘다.

const _gateLeave = '거절하고 나가기'; // trust_gate_sheet.dart:91
const _gateChange = '변경'; // trust_gate_sheet.dart:181 — 아이디 칸 오른쪽 TextButton
const _gateLeaveConfirm = '나가기'; // chat_dialogs.dart:16 — 나가기 확인 창의 빨간 버튼
const _gateLeaveTitle = '채팅방을 나갈까요?'; // chat_dialogs.dart:13
const _kakaoFieldLabel = '카카오톡 아이디'; // kakao_id_settings_screen.dart:68 — 16e-1 입력칸 라벨
const _kakaoSave = '저장'; // kakao_id_settings_screen.dart:88
final RegExp _countdownText = RegExp(r'^\d{2,}:\d{2}:\d{2}$'); // chat_time.dart countdownLabel — 시트 카운트다운(배너 문장은 이 모양이 아니다)

String _utcNow() => DateTime.now().toUtc().toIso8601String();

/// 시트가 뜨고 올라오는 동안은 버튼이 제자리가 아니다 — 제목이 보이면 두 번 쉬어 멈춘 뒤에 쓴다.
Future<bool> _gateSheetUp(WidgetTester tester, {Duration within = const Duration(seconds: 30)}) async {
  if (!await _ever(tester, find.text(_sheetTitle), within)) return false;
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 800));
  return true;
}

/// 시트가 보여 주는 내 카카오톡 아이디(시트 위젯이 받은 값) — 시트가 없으면 null.
String? _sheetKakaoId(WidgetTester tester) {
  final sheet = find.byType(TrustGateSheet);
  return sheet.evaluate().isEmpty ? null : tester.widget<TrustGateSheet>(sheet).myKakaoId;
}

/// 시트의 남은 시간 글자 "HH:MM:SS" — 없으면 null.
String? _sheetCountdown(WidgetTester tester) {
  final texts = find.byWidgetPredicate((w) => w is Text && _countdownText.hasMatch(w.data ?? ''));
  return texts.evaluate().isEmpty ? null : tester.widget<Text>(texts.first).data;
}

Finder _roomTitle(String nickname) => find.descendant(of: find.byType(AppBar), matching: find.text(nickname));

/// E-CHAT-45 — 방을 열어 시트의 제목 · 내 아이디 · 남은 시간을 읽는다. 남은 시간을 읽은 순간의 앱 시계(UTC)를 같이 말한다.
Future<Map<String, Object?>> _sheetSeen(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final up = await _gateSheetUp(tester);
  final countdown = _sheetCountdown(tester);
  final shownAt = _utcNow(); // 위 줄과 같은 틈에서 — 사이에 프레임을 돌리지 않는다
  return {'sheet': up, 'sheet_id': _sheetKakaoId(tester), 'countdown': countdown, 'shown_at': shownAt};
}

/// 시트를 아래로 민다. 제목 글자를 잡고 한 번, 안 닫히면 시트 맨 위(손잡이 줄)를 잡고 한 번 더. 닫힌 밀기 횟수(둘 다 안 닫히면 0).
Future<int> _swipeSheetAway(WidgetTester tester) async {
  final title = find.text(_sheetTitle);
  await tester.fling(title, const Offset(0, 600), 1500);
  await wait(tester, const Duration(seconds: 1));
  if (!_has(title)) return 1;
  final top = tester.getTopLeft(find.byType(TrustGateSheet));
  await tester.flingFrom(top + const Offset(150, 8), const Offset(0, 600), 1500);
  await wait(tester, const Duration(seconds: 1));
  return _has(title) ? 0 : 2;
}

/// E-CHAT-46 — 시트를 밀어 닫으면 14h 배너, 뒤로 갔다가 같은 방을 다시 열면 시트가 또 뜬다(방마다 State 가 새로 생기고 뷰모델도 버려진다).
Future<Map<String, Object?>> _swipeAway(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  await _openRoom(tester, nickname);
  final up = await _gateSheetUp(tester);
  if (!up) return {'sheet': false};
  final swipes = await _swipeSheetAway(tester);
  await wait(tester, const Duration(seconds: 1)); // 닫히며 sheetDismissed → 배너
  final banners = _banners(tester);
  await tap(tester, find.byType(BackButton));
  await pumpUntil(tester, _row(nickname)); // 대화 목록으로 — 방이 덮고 있는 동안은 줄이 안 보인다
  await tap(tester, _row(nickname));
  await pumpUntil(tester, _roomTitle(nickname));
  return {'sheet': true, 'swipes': swipes, 'banners': banners, 'again': await _ever(tester, find.text(_sheetTitle), const Duration(seconds: 10))};
}

/// E-CHAT-47 — 대화 목록에서 그 방 줄을 찾은 채 멈춰 PC 가 방 시각을 옮기게 한 뒤(`step`) 줄을 눌러 방을 열고, 시트가 뜰 때까지(90초) 잰다.
/// 방을 연 순간 = 앱바에 상대 닉네임이 뜬 때(방을 읽은 직후 — 경계 Timer 도 그때 걸린다). 시각은 앱 시계, 걸린 시간은 Stopwatch.
Future<Map<String, Object?>> _sheetOnBoundary(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  await _toConversations(tester);
  await pumpUntil(tester, _row(nickname));
  await step('move'); // PC 가 방의 created_at 을 지금 − 23시간 59분으로 옮긴다 — 방을 읽기 전이라야 앱이 새 값을 받는다
  await tap(tester, _row(nickname));
  await pumpUntil(tester, _roomTitle(nickname));
  final openAt = _utcNow();
  final atOpen = _has(find.text(_sheetTitle));
  final shown = await appears(tester, find.text(_sheetTitle), const Duration(seconds: 90));
  return {'open_at': openAt, 'sheet_at_open': atOpen, 'sheet': shown != null, 'sheet_ms': shown?.inMilliseconds};
}

/// E-CHAT-48 — 시트의 "변경" → 16e-1 에서 저장된 아이디가 칸에 채워진 뒤 새 값으로 바꿔 "저장" → 돌아오면(방을 다시 읽는다) 시트의 아이디.
Future<Map<String, Object?>> _changeKakaoFromSheet(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  must(await _gateSheetUp(tester), '14f 시트가 안 뜸');
  final before = _sheetKakaoId(tester);
  await tap(tester, find.widgetWithText(TextButton, _gateChange));
  final field = labeled(_kakaoFieldLabel);
  await pumpUntil(tester, field);
  final stored = job['kakao'] as String;
  final watch = Stopwatch()..start();
  while (fieldText(tester, field) != stored) { // 저장된 값이 늦게 채워지며 방금 쓴 글을 덮지 않게 채워진 뒤에 쓴다
    must(watch.elapsed < const Duration(seconds: 15), '16e-1 입력칸이 "$stored" 로 안 채워짐(${fieldText(tester, field)})');
    await tester.pump(const Duration(milliseconds: 200));
  }
  final value = job['value'] as String;
  await type(tester, field, value);
  await tap(tester, button(_kakaoSave));
  String? after;
  final back = Stopwatch()..start();
  while (back.elapsed < const Duration(seconds: 20)) { // 저장 → 16e-1 닫힘 → 방 다시 읽기 → 시트가 새 아이디를 그린다
    await tester.pump(const Duration(milliseconds: 200));
    after = _sheetKakaoId(tester);
    if (after == value) break;
  }
  return {'sheet_before': before, 'sheet_after': after};
}

/// E-CHAT-49 — 시트의 "거절하고 나가기" → 나가기 확인 창의 "나가기" → 방이 닫히고 내 대화 목록에서 그 줄이 사라질 때까지(2초 연속 없음).
Future<Map<String, Object?>> _rejectAndLeave(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  await _openRoom(tester, nickname);
  final up = await _gateSheetUp(tester);
  if (!up) return {'sheet': false};
  await tap(tester, button(_gateLeave));
  final confirm = await _ever(tester, find.text(_gateLeaveTitle), const Duration(seconds: 10));
  if (!confirm) return {'sheet': true, 'confirm': false};
  await tester.pump(const Duration(milliseconds: 800)); // 창이 멈춘 뒤에 누른다
  await tester.pump(const Duration(milliseconds: 800));
  await tap(tester, find.widgetWithText(TextButton, _gateLeaveConfirm));
  var gone = false;
  final watch = Stopwatch()..start();
  while (!gone && watch.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.byType(ConversationsScreen).evaluate().isEmpty || _has(_row(nickname))) continue; // 아직 방 · 옛 목록
    await wait(tester, const Duration(seconds: 2)); // 목록을 다시 읽는 사이의 빈 순간이 아닌지
    gone = !_has(_row(nickname));
  }
  return {'sheet': true, 'confirm': true, 'row_gone': gone};
}

/// E-CHAT-56 — 응답 기한(48시간)이 지난 방(배치는 아직)을 열어 시트의 "수락하고 공유하기"(시트는 확인 창이 없다)를 누르고, 방 뷰모델에 처음 뜬 오류 문구.
/// 시트가 닫히며 dismissSheet 의 copyWith 가 오류 줄을 지울 수 있어 처음 값을 구독으로 잡고, 끝 값도 같이 말한다.
Future<Map<String, Object?>> _acceptAfterDeadline(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final matchId = tester.widget<ChatRoomScreen>(room).matchId;
  String? first;
  final sub = container.listen(chatRoomViewModelProvider(matchId), (_, next) => first ??= next.errorMessage);
  try {
    final up = await _gateSheetUp(tester);
    if (!up) return {'sheet': false};
    await tap(tester, button(_acceptSheet));
    final watch = Stopwatch()..start();
    while (first == null && watch.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await wait(tester, const Duration(seconds: 1));
    return {'sheet': true, 'error': first, 'error_now': container.read(chatRoomViewModelProvider(matchId)).errorMessage};
  } finally {
    sub.close();
  }
}

final Map<String, Area1Case> area3Cases4 = {
  'E-CHAT-45': _session(_sheetSeen),
  'E-CHAT-46': _session(_swipeAway),
  'E-CHAT-47': _session(_sheetOnBoundary),
  'E-CHAT-48': _session(_changeKakaoFromSheet),
  'E-CHAT-49': _session(_rejectAndLeave),
  'E-CHAT-56': _session(_acceptAfterDeadline),
};
