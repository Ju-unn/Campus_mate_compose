part of 'area4.dart';

// 영역 4 PUSH A2 — 알림을 눌러 그 화면이 열리는지 10개. PC 쪽은 e2e/area4_push_tap.py 의 같은 번호(계정 · 상대 행동 · 알림 읽기 · 알림 누르기는 전부 PC).
// 앱은 도착한 화면에서 본 것만 Map 으로 말하고 판정은 PC 가 한다. 일감은 세 판이다 — `hold`(뒤: 홈에서 멈춰 기다리다 눌린 뒤 화면을 본다),
// `login`(꺼짐: 로그인해 홈까지 가 알림 토큰이 올라가게 둔다), `tap`(꺼짐: 알림 누름으로 콜드 스타트한 앱이 e2e_test.dart 의 hear() 로 받는다 —
// `_session` 으로 안 감싸 새 로그인을 하지 않는다. 앞 판이 저장한 세션이 살아 있어야 한다). 경로는 main.dart · push_route.dart 쪽이다.

const _pushTapCases = ['11', '19', '27', '28', '38', '50', '76', '77', '78', '81'];
const _pushScreenWait = Duration(seconds: 30); // 로그인 · 관문 조회 · 라우터가 눌러 둔 경로를 받아 주는 시간(꺼진 앱은 부팅 포함)
const _pushContentWait = Duration(seconds: 10); // 화면이 열린 뒤 사람 · 글이 그려지는 시간

/// 지금 보이는 화면 이름들 — 도착 화면이 안 열렸을 때 약관 · 온보딩 · 로그인 어디에 머무는지 PC 가 가린다(area1.dart `screens` 의 키).
List<String> _pushScreens() => [
      for (final name in const ['login', 'consent', 'consent-renew', '3b', '3c', '04-1', 'home']) if (screen(name).evaluate().isNotEmpty) name,
    ];

/// 도착 화면에서 본 것 — 화면이 열렸나(dest) · 그 사람이 보이나(who) · (일감에 body 가 있으면) 방금 글이 보이나(body).
Future<Map<String, Object?>> _pushArrived(WidgetTester tester, Map<String, dynamic> job) async {
  final dest = job['dest'] as String;
  final nickname = job['nickname'] as String;
  final body = job['body'] as String?;
  final watch = Stopwatch()..start(); // 일감을 받은 때(앱이 부팅하고 hear() 가 끝난 뒤)부터 — 알림을 누른 때가 아니다
  final reached = switch (dest) {
    'conversations' => find.byType(ConversationsScreen),
    'room' => find.byType(ChatRoomScreen),
    _ => find.byType(ReceivedReviewsScreen),
  };
  final opened = await appears(tester, reached, _pushScreenWait) != null;
  final ms = watch.elapsedMilliseconds;
  var who = false;
  var said = false;
  if (opened) {
    final person = switch (dest) {
      'conversations' => find.descendant(
          of: find.byType(job['section'] == 'acceptance' ? AcceptanceRow : ChatListRow), matching: find.textContaining(nickname)),
      'room' => find.descendant(of: find.byType(AppBar), matching: find.text(nickname)),
      _ => find.descendant(of: find.byType(FriendReviewCard), matching: find.textContaining(nickname)),
    };
    who = await appears(tester, person, _pushContentWait) != null;
    if (body != null) {
      said = await appears(tester, find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == body, skipOffstage: false), _pushContentWait) != null;
    }
  }
  return {'dest': opened, 'who': who, if (body != null) 'body': said, 'screen': _pushScreens(), 'ms': ms};
}

Future<Map<String, Object?>?> _pushTapCase(WidgetTester tester, Map<String, dynamic> job) async => switch (job['phase']) {
      'hold' => await _session((tester, job) async {
          await arrive(tester, 'home');
          await wait(tester, const Duration(seconds: 3));
          await step('holding', timeout: const Duration(minutes: 4)); // PC 가 HOME · 상대 행동 · 알림 읽기 · 누르기를 하는 동안
          return _pushArrived(tester, job);
        })(tester, job),
      'login' => await _session((tester, job) async {
          await arrive(tester, 'home');
          await wait(tester, const Duration(seconds: 3));
          return null;
        })(tester, job),
      'tap' => await _pushArrived(tester, job),
      final other => throw E2eBlocked('E-PUSH 일감 phase 를 모름: $other'),
    };

final Map<String, Area1Case> _pushTapMap = {for (final number in _pushTapCases) 'E-PUSH-$number': _pushTapCase};
