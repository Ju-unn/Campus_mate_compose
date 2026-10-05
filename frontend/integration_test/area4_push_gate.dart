part of 'area4.dart';

// 영역 4 PUSH 채팅 게이트 배치(chat-gate) 11개 — 40~48 · 79 · 80. PC 쪽은 e2e/area4_push_gate.py 의 같은 번호(계정 · 매칭 · 배치 · 알림 읽기는 전부 PC).
// 앱이 하는 일은 번호마다 다르다.
//  · 40 41 43 44 45 46 47 48 — 로그인해 홈까지 가서 알림 토큰이 올라가게 두고 3초 머문다(영역 1 E-ONB-61 과 같은 동작). 알림 확인은 PC 가 한다.
//  · 42 — 홈에서 멈춘다(`step`). PC 가 앱을 뒤로 보내고 배치를 불러 알림을 누르면, 앱은 열린 방(ChatRoomScreen)과 앱바 닉네임을 본다. 앱이 살아 있는 채 눌리는 판이다.
//  · 79 — 두 판이다. phase 없음은 홈까지(위와 같다), phase tap 은 PC 가 앱을 죽인 뒤 알림을 눌러 콜드 스타트한 앱이(e2e_test.dart 의 hear()) 방을 연다.
//        E-CHAT-32(area3_b3.dart)와 같은 방식이고 메시지 본문 확인만 뺐다. tap 판은 `_session` 으로 안 감싸 앞 판이 저장한 세션을 그대로 쓴다.
//  · 80 — 대화 탭을 앞에 두고 멈춘다. PC 가 배치를 부르고 60초 지켜본 뒤(앞에서는 배너가 없다) 돌려보내면, 앱은 대화 목록과 상대 줄이 그대로인지 본다.

const _gateLongStep = Duration(minutes: 8); // PC 가 배치 · 앵커 확인 · 60초 지켜보기 · 대조를 하는 동안 멈춰 있는 시간
const _gateRoomWait = Duration(seconds: 30); // 알림으로 켜진/돌아온 앱이 방을 여는 시간(로그인 · 관문 조회 · 라우터가 눌러 둔 경로를 받아 주는 시간)
const _gateContentWait = Duration(seconds: 10); // 방이 열린 뒤 앱바 닉네임이 그려지는 시간(시나리오 10초)

/// 지금 보이는 화면 이름들 — 방이 안 열렸을 때 약관 · 온보딩 · 로그인 어디에 머무는지 PC 가 가린다. 이름은 area1.dart `screens` 의 키와 같고,
/// 대화 목록은 알림 경로가 방 id 없이 목록으로 떨어진 경우를 위해 더했다(area3_b3.dart `_screensNow` 와 같다).
List<String> _gateScreensNow() {
  final seen = <String, Finder>{
    for (final name in const ['login', 'consent', 'consent-renew', '3b', '3c', '04-1', 'home']) name: screen(name),
    'conversations': find.byType(ConversationsScreen),
  };
  return [for (final entry in seen.entries) if (entry.value.evaluate().isNotEmpty) entry.key];
}

/// 대화 목록의 [nickname] 줄.
Finder _gateRow(String nickname) => find.byWidgetPredicate((w) => w is ChatListRow && w.conversation.partner.nickname == nickname);

/// 알림을 눌러 방이 열릴 때까지 기다려 본 것을 말한다. 방이 안 열려도 던지지 않고 본 대로 말한다 — 판정은 PC.
Future<Map<String, Object?>> _gateRoomOpened(WidgetTester tester, String nickname) async {
  final watch = Stopwatch()..start(); // 일감을 받은 때(또는 PC 가 누른 뒤 돌려보낸 때)부터 — 앱 부팅 시간이 들어간다
  final room = await appears(tester, find.byType(ChatRoomScreen), _gateRoomWait) != null;
  final roomMs = watch.elapsedMilliseconds;
  final openedAt = DateTime.now().toUtc().toIso8601String();
  final shownNickname = room &&
      await appears(tester, find.descendant(of: find.byType(AppBar), matching: find.text(nickname)), _gateContentWait) != null;
  return {'room': room, 'nickname': shownNickname, 'screen': _gateScreensNow(), 'room_ms': roomMs, 'opened_at': openedAt};
}

final Map<String, Area1Case> _pushGateCases = {
  for (final number in const ['40', '41', '43', '44', '45', '46', '47', '48']) 'E-PUSH-$number': area1Cases['E-ONB-61']!,
  'E-PUSH-42': _session((tester, job) async {
    await arrive(tester, 'home');
    final go = await step('ready', timeout: _gateLongStep); // PC: 토큰 확인 → 뒤로 → 배치 → 알림 → 누르기(알림이 안 왔으면 tapped: false)
    if (go['tapped'] != true) return {'skipped': true};
    return _gateRoomOpened(tester, job['nickname'] as String);
  }),
  'E-PUSH-79': (tester, job) async => job['phase'] == 'tap'
      ? _gateRoomOpened(tester, job['nickname'] as String)
      : area1Cases['E-ONB-61']!(tester, job),
  'E-PUSH-80': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await arrive(tester, 'home');
    await tap(tester, _tab('대화'));
    await pumpUntil(tester, _gateRow(nickname));
    await step('front', timeout: _gateLongStep); // PC: 배치 → 앞에서 60초 0개 → 뒤로 → 대조 → 다시 앞으로
    await wait(tester, const Duration(seconds: 2)); // 앞으로 돌아와 목록이 다시 그려질 틈
    return {
      'list': find.byType(ConversationsScreen).evaluate().isNotEmpty,
      'row': _gateRow(nickname).evaluate().isNotEmpty,
      'screen': _gateScreensNow(),
    };
  }),
};
