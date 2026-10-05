part of 'area4.dart';

// 영역 4 PUSH 카드 배치 9개(E-PUSH-01~09). PC 쪽은 e2e/area4_push_card.py 의 같은 번호 — 계정 · 배치 · 알림 읽기 · 누르기는 전부 PC 가 한다.
// 01 · 05 · 06 · 07 · 08 · 09 는 알림이 오는지 · 안 오는지만 보므로 앱은 로그인해 홈까지 가서 알림 토큰이 올라가게 두고 3초 머문다(영역 1 E-ONB-61 과 같은 동작).
// 02 · 04 는 이미 있는 앱 가설(E-CARD-02 · E-CARD-03)의 별칭이라 e2e_test.dart 에서 건다 — area2_c.dart · area2_d.dart 의 가설은 그 파일에서만 같이 보인다.
// 03 만 새로다 — 꺼진 앱에서 카드 알림을 눌러 켜지면 오늘 탭(/today)에 카드 1장이 뜨는지. E-CHAT-32(area3_b3.dart)와 같은 두 판이다:
// `phase: login` 은 로그인해 홈까지 가서 토큰이 올라가게 두고, `phase: tap` 은 알림 누름으로 켜진 앱이(e2e_test.dart 의 hear() 로) 받는다.
// tap 판은 `_session` 으로 안 감싸 새 로그인을 하지 않는다 — 앞 판이 저장한 세션이 그대로 살아 있어야 한다.
// 경로는 main.dart 의 initialMessage → _openRoute(A10: 라우터가 받아 줄 때만 연다) 쪽이다. 약관 · 홈에 머물면 오늘 탭을 놓친 것(회귀).

const _cardTodayWait = Duration(seconds: 30); // 로그인 · 관문 조회 · 라우터가 눌러 둔 경로를 받아 주는 시간
const _cardLoadWait = Duration(seconds: 15); // 오늘 탭이 열린 뒤 카드가 그려지는 시간
const _cardTodayTitle = '오늘의 카드'; // today_cards_screen.dart 앱바 제목(area2_c.dart `_todayTitle` 과 같다)

/// 지금 보이는 화면 이름들 — 오늘 탭이 안 열렸을 때 약관 · 온보딩 · 홈 어디에 머무는지 PC 가 가린다.
/// 이름은 area1.dart `screens` 의 키와 같고(`screen` 으로 찾는다), 오늘 탭은 화면 종류로 찾는다.
List<String> _cardScreensNow() {
  final seen = <String, Finder>{
    for (final name in const ['login', 'consent', 'consent-renew', '3b', '3c', '04-1', 'home']) name: screen(name),
    'today': find.byType(TodayCardsScreen),
  };
  return [for (final entry in seen.entries) if (entry.value.evaluate().isNotEmpty) entry.key];
}

/// phase tap — 알림으로 콜드 스타트한 앱이 오늘 탭을 열 때까지 기다려 본 것을 말한다. 안 열려도 던지지 않고 본 대로 말한다(PC 가 판정).
Future<Map<String, Object?>?> _cardOpenedByNotification(WidgetTester tester, Map<String, dynamic> job) async {
  final watch = Stopwatch()..start(); // 일감을 받은 때(앱이 부팅하고 hear() 가 끝난 뒤)부터 — 알림을 누른 때가 아니다
  final today = await appears(
          tester, find.descendant(of: find.byType(TodayCardsScreen), matching: find.text(_cardTodayTitle)), _cardTodayWait) !=
      null;
  final openedAt = DateTime.now().toUtc().toIso8601String();
  final todayMs = watch.elapsedMilliseconds;
  var cards = 0;
  if (today) {
    await appears(tester, find.byType(DailyCardSummary), _cardLoadWait); // 카드 조회가 끝나기를
    await wait(tester, const Duration(seconds: 2)); // 같은 카드가 더 늘어나는지 조금 더
    cards = find.byType(DailyCardSummary).evaluate().length;
  }
  return {
    'today': today,
    'cards': cards,
    'today_ms': todayMs,
    'screen': _cardScreensNow(),
    'opened_at': openedAt,
  };
}

final Map<String, Area1Case> _pushCardCases = {
  'E-PUSH-01': area1Cases['E-ONB-61']!,
  'E-PUSH-03': (tester, job) async => switch (job['phase']) {
        'login' => await area1Cases['E-ONB-61']!(tester, job),
        'tap' => await _cardOpenedByNotification(tester, job),
        final other => throw E2eBlocked('E-PUSH-03 일감 phase 를 모름: $other'),
      },
  'E-PUSH-05': area1Cases['E-ONB-61']!,
  'E-PUSH-06': area1Cases['E-ONB-61']!,
  'E-PUSH-07': area1Cases['E-ONB-61']!,
  'E-PUSH-08': area1Cases['E-ONB-61']!,
  'E-PUSH-09': area1Cases['E-ONB-61']!,
};
