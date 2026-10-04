part of 'area3.dart';

// 영역 3 폰 A 한 대 3차 — 꺼진 앱에서 알림을 눌러 방이 열리는 E-CHAT-32 한 개. PC 쪽은 e2e/area3_phone3.py 의 같은 번호(계정 · 매칭을 만들고,
// 앱을 죽이고, 상대가 보내고, 알림을 눌러 이 앱을 콜드 스타트시킨다). 앱은 열린 방에서 본 것만 Map 으로 돌려주고 판정은 PC 가 한다.
// 일감은 두 판이다 — `phase: login` 은 로그인해 홈까지 가서 알림 토큰이 올라가게 두고, `phase: tap` 은 알림 누름으로 켜진 앱이
// (e2e_test.dart 의 hear() 로) 받는다. tap 판은 `_session` 으로 안 감싸 새 로그인을 하지 않는다 — 앞 판이 저장한 세션이 그대로 살아 있어야 한다.
// 경로는 main.dart:106-120(initialMessage → _openRoute) · 160-190(라우터가 받아 줄 때 연다) 쪽이다.

const _pushRoomWait = Duration(seconds: 30); // 로그인 · 관문 조회 · 라우터가 눌러 둔 경로를 받아 주는 시간
const _pushContentWait = Duration(seconds: 10); // 방이 열린 뒤 닉네임 · 메시지가 그려지는 시간(시나리오 10초)

/// 지금 보이는 화면 이름들 — 방이 안 열렸을 때 약관 · 온보딩 · 로그인 어디에 머무는지 PC 가 가린다.
/// 이름은 area1.dart `screens` 의 키와 같고(`screen` 으로 찾는다), 대화 목록은 알림 경로가 방 id 없이 목록(push_route.dart `_chatRoom`)으로 떨어진 경우를 위해 더했다.
List<String> _screensNow() {
  final seen = <String, Finder>{
    for (final name in const ['login', 'consent', 'consent-renew', '3b', '3c', '04-1', 'home']) name: screen(name),
    'conversations': find.byType(ConversationsScreen),
  };
  return [for (final entry in seen.entries) if (entry.value.evaluate().isNotEmpty) entry.key];
}

/// phase login — 로그인해 홈까지(알림 토큰 등록은 홈에 닿은 뒤 앱이 알아서 한다). 말할 것은 없다.
Future<Map<String, Object?>?> _homeAfterLogin(WidgetTester tester, Map<String, dynamic> job) async {
  await arrive(tester, 'home');
  return {};
}

/// phase tap — 알림으로 콜드 스타트한 앱이 그 방을 열 때까지 기다려 본 것을 말한다. 방이 안 열려도 던지지 않고 본 대로 말한다.
Future<Map<String, Object?>?> _openedByNotification(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  final body = job['body'] as String;
  final watch = Stopwatch()..start(); // 일감을 받은 때(앱이 부팅하고 hear() 가 끝난 뒤)부터 — 알림을 누른 때가 아니다
  final room = await appears(tester, find.byType(ChatRoomScreen), _pushRoomWait) != null;
  final openedAt = DateTime.now().toUtc().toIso8601String();
  final roomMs = watch.elapsedMilliseconds;
  var shownNickname = false;
  var shownMessage = false;
  if (room) {
    shownNickname =
        await appears(tester, find.descendant(of: find.byType(AppBar), matching: find.text(nickname)), _pushContentWait) != null;
    shownMessage = await appears(
            tester, find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == body, skipOffstage: false), _pushContentWait) !=
        null;
  }
  return {
    'room': room,
    'nickname': shownNickname,
    'message': shownMessage,
    'screen': _screensNow(),
    'room_ms': roomMs,
    'opened_at': openedAt,
  };
}

final Map<String, Area1Case> area3Cases3 = {
  'E-CHAT-32': (tester, job) async => switch (job['phase']) {
        'login' => await _session(_homeAfterLogin)(tester, job),
        'tap' => await _openedByNotification(tester, job),
        final other => throw E2eBlocked('E-CHAT-32 일감 phase 를 모름: $other'),
      },
};
