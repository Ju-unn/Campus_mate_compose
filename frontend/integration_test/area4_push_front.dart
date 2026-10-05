part of 'area4.dart';

// 영역 4 PUSH A3 — 앱이 앞에 있을 때 알림은 안 뜨고 화면만 바뀌는지 7개. PC 쪽은 e2e/area4_push_front.py 의 같은 번호(계정 · 상대 행동 · 알림 읽기는 전부 PC).
// 앱이 하는 일은 셋이다 — 홈에서 멈춰 PC 가 토큰을 기다리게 하고(`home`), 그 화면으로 가 앞에 머문 채 멈춰 PC 가 상대 행동을 부르게 하고(`ready`),
// 화면이 저절로 바뀌었는지 본 대로 말한다(`judged` 에서 PC 가 알림 0개를 지켜보는 동안 멈춤). 31 은 방에 들어갔다 나온 뒤(`left`) PC 가 HOME 으로 내린다.

const _pushFrontCases = ['14', '20', '29', '30', '31', '53', '82'];
const _pushFrontWait = Duration(seconds: 30); // 화면이 저절로 바뀌기를 기다리는 시간(시나리오 T)
const _pushRoomMessageWait = Duration(seconds: 10); // 29: 방에서 메시지 줄이 보이기를 기다리는 시간(시나리오 2초 — 걸린 ms 를 메모에 남긴다)
const _pushHold = Duration(minutes: 4); // PC 가 하는 일(토큰 대기 · 31초 기다림 · 알림 60초 지켜보기 · 대조) 동안 앱은 기다린다

BuildContext _pushContext(WidgetTester tester) => tester.element(find.byType(Scaffold).first);

/// 앞에 있어야 할 화면(PC 일감의 screen).
Finder _pushScreenFinder(String screen) => switch (screen) {
      'conversations' => find.byType(ConversationsScreen),
      'room' => find.byType(ChatRoomScreen),
      'reviews' => find.byType(ReceivedReviewsScreen),
      _ => find.byType(TodayCardsScreen),
    };

/// 그 화면으로 간다 — 방 · 받은 리뷰는 라우터로 열고(방은 push 라 뒤로 나올 수 있다), 대화 목록 · 오늘은 하단 내비 탭을 누른다.
Future<void> _pushGo(WidgetTester tester, Map<String, dynamic> job) async {
  final screen = job['screen'] as String;
  switch (screen) {
    case 'conversations':
      await tap(tester, _tab('대화'));
    case 'today':
      await tap(tester, _tab('오늘'));
    case 'room':
      unawaited(GoRouter.of(_pushContext(tester)).push('${AppRoutes.chatRoom}/${job['match_id']}'));
    default:
      unawaited(GoRouter.of(_pushContext(tester)).push(AppRoutes.friendReviews));
  }
  await pumpUntil(tester, _pushScreenFinder(screen), timeout: _pushFrontWait);
  await wait(tester, const Duration(seconds: 1));
}

Finder _pushRow(String nickname) => find.byWidgetPredicate((w) => w is ChatListRow && w.conversation.partner.nickname == nickname);

Finder _pushReviewCard(String nickname) => find.descendant(of: find.byType(FriendReviewCard), matching: find.textContaining(nickname));

/// 화면이 저절로 바뀌었는지 — 일감의 번호에 맞는 것만 본다. PC 가 상대 행동을 부른 직후부터 센다.
Future<Map<String, Object?>> _pushJudge(WidgetTester tester, String number, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  final seen = <String, Object?>{};
  final watch = Stopwatch()..start();
  switch (number) {
    case '14':
      seen['row'] = await appears(tester, find.descendant(of: find.byType(AcceptanceRow), matching: find.textContaining(nickname)), _pushFrontWait) != null;
    case '20':
      seen['row'] = await appears(tester, _pushRow(nickname), _pushFrontWait) != null;
    case '29':
      seen['body'] = await appears(
              tester, find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == job['body'], skipOffstage: false), _pushRoomMessageWait) !=
          null;
      seen['ms'] = watch.elapsedMilliseconds;
    case '82':
      seen['badge'] = await appears(tester, find.descendant(of: find.byType(AppBottomNav), matching: find.text('1')), _pushFrontWait) != null;
    case '53':
      // 앞에서는 화면 갱신이 없다 — 한참 기다려도 줄이 안 생기고, 나갔다 다시 들어가야 1줄이 보인다.
      await wait(tester, const Duration(seconds: 10));
      seen['absent'] = _pushReviewCard(nickname).evaluate().isEmpty;
      GoRouter.of(_pushContext(tester)).pop();
      await wait(tester, const Duration(seconds: 1));
      unawaited(GoRouter.of(_pushContext(tester)).push(AppRoutes.friendReviews));
      seen['present'] = await appears(tester, _pushReviewCard(nickname), _pushFrontWait) != null;
  }
  seen['front'] = _pushScreenFinder(job['screen'] as String).evaluate().isNotEmpty;
  return seen;
}

Area1Case _pushFrontCase(String number) => _session((tester, job) async {
      await arrive(tester, 'home');
      await wait(tester, const Duration(seconds: 3));
      await step('home', timeout: _pushHold); // PC: 기기 토큰이 서버에 올라오기를 기다린다
      await _pushGo(tester, job);
      if (number == '31') {
        // 방에 들어갔다 바로 나온다 — 나갈 때 읽음이 찍힌다. 그 뒤 PC 가 HOME 으로 내리고 10초 · 40초에 메시지를 보낸다.
        await wait(tester, const Duration(seconds: 2));
        GoRouter.of(_pushContext(tester)).pop();
        await wait(tester, const Duration(seconds: 1));
        await step('left', timeout: _pushHold);
        return null;
      }
      await step('ready', timeout: _pushHold); // PC: 상대가 행동한다(30 은 31초 기다린 뒤)
      final seen = await _pushJudge(tester, number, job);
      await step('judged', timeout: _pushHold); // PC: 알림이 0개인지 지켜보고, HOME 으로 내려 대조 알림을 본다
      return seen;
    });

final Map<String, Area1Case> _pushFrontMap = {for (final number in _pushFrontCases) 'E-PUSH-$number': _pushFrontCase(number)};
