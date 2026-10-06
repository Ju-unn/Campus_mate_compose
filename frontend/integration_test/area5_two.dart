part of 'area5.dart';

// 영역 5 두 기기(폰 A + 에뮬 B) 탈퇴 5개(묶음 area5-two — E-WD-05 · 06 · 07 · 08 · 09). PC 쪽은 e2e/area5_two.py 의 같은 번호 —
// 열쇠는 `번호/A`(폰) · `번호/B`(에뮬)이고, 두 앱이 서로 기다리는 순서는 PC 가 `step` 에서 잇는다(e2e/twodev.py).
// A 는 늘 "정말 영구 삭제" 를 실제로 누른다 — [_twoWithdrawA] 한 곳에서만 area5_wd.dart 의 _wdOpenFinal · _wdWithdraw · _wdToLogin 을 부르고,
// 거기 닿는 것은 `/A` 다섯뿐이다(e2e/test_area5_two.py 가 고정). B 쪽은 탈퇴 · 나가기 버튼을 누르지 않는다(있는지만 본다).
// B 는 목록이 처음 읽을 때 굳으므로(area2_two_accept.dart 머리말) 로그아웃한 채 멈췄다가 PC 가 go 에 실어 준 새 토큰으로 로그인한다.
// 화면 판정은 앱이 must 로(어긋나면 fail), DB 판정은 PC 가 한다. 이 파일의 이름은 모두 `_two` 로 시작한다.
// 이 파일은 클라우드 세션에서 Flutter 없이 썼다 — `flutter analyze` · 기기 실행은 아직이다.

const _twoWithdrawn = '탈퇴한 계정이에요'; // common/failure.dart WithdrawnFailure
const _twoWrittenEntry = '내가 쓴 리뷰'; // my_friend_reviews_section.dart
const _twoWrittenEmpty = '아직 쓴 리뷰가 없어요'; // written_reviews_screen.dart
const _twoChatEmpty = '아직 시작된 대화가 없어요'; // conversations_screen.dart
const _twoLongWait = Duration(minutes: 10); // 상대 기기 · 배치를 기다리는 멈춤(support.step 기본은 2분)
const _twoLoadWait = Duration(seconds: 20);
// 오늘 탭(today_cards_screen.dart)이 다 그려졌다는 표시 — 카드가 없을 때의 안내 글 중 하나, 또는 카드 한 장
const _twoTodayEmpty = ['지금은 소개할 사람이 없어요', '오늘 카드는 확인했어요', '새로운 사람이 준비되면 알려드릴게요'];

Future<void> _twoSignOut() => Supabase.instance.client.auth.signOut(scope: SignOutScope.local);

/// 로그아웃한 채 [name] 에서 멈췄다가 PC 가 준 새 토큰으로 로그인해 [body] 를 돈다.
Area1Case _twoLoginAfter(String name, Area1Case body) => (tester, job) async {
      await _twoSignOut();
      final go = await step(name, timeout: _twoLongWait);
      await signIn(go['token_hash'] as String);
      return body(tester, job);
    };

/// A 쪽 — 홈까지 간 뒤 나 탭 → 설정 → 탈퇴하기 → 영구 삭제 → "정말 영구 삭제" 를 눌러 02 + "탈퇴한 계정이에요" 까지. 이 파일에서 탈퇴를 누르는 곳은 여기 하나다.
Future<void> _twoWithdrawA(WidgetTester tester) async {
  await _wdOpenFinal(tester);
  await _wdWithdraw(tester);
  final login = await _wdToLogin(tester);
  must(login['login_ms'] != null, 'A: 탈퇴 버튼을 누른 뒤 02(로그인 화면)에 못 닿음');
  must(login['notice'] == _twoWithdrawn, 'A: 02 알림 ${login['notice']}(기대 $_twoWithdrawn)');
}

/// A 의 기본 흐름 — 로그인 → 홈 → 탈퇴 → `withdrawn` 에서 멈춤(PC 가 DB 로 탈퇴를 보고 B 를 보낸다).
Area1Case _twoA() => _session((tester, job) async {
      await arrive(tester, 'home');
      await _twoWithdrawA(tester);
      await step('withdrawn', timeout: _twoLongWait);
      return null;
    });

/// 02 가 뜰 때까지(최대 [_wdLoginWait]) 기다리고, 뜨면 2초 안에 알림 글자를 읽는다 → (02 에 닿음, 알림).
Future<(bool, String?)> _twoLoginNotice(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < _wdLoginWait && !_has(screen('login'))) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!_has(screen('login'))) return (false, null);
  String? notice;
  final look = Stopwatch()..start();
  while (notice == null && look.elapsed < const Duration(seconds: 2)) {
    notice = _wdToast(tester);
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (true, notice);
}

/// 오늘 탭을 열어 다 그려질 때까지 — 카드 한 장 또는 빈 안내 글. 안 그려지면 판정할 수 없다(blocked).
Future<void> _twoOpenToday(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('오늘'));
  final drawn = find.byWidgetPredicate((w) =>
      w is DailyCardSummary || (w is Text && (_twoTodayEmpty.contains(w.data) || (w.data ?? '').startsWith('내일 '))));
  if (await appears(tester, drawn, _twoLoadWait) == null) throw E2eBlocked('오늘 탭이 $_twoLoadWait 안에 안 그려짐');
  await wait(tester, const Duration(seconds: 1)); // 카드가 늦게 붙는 일이 없는지
}

/// 오늘 탭에 [nickname] 카드가 없다.
void _twoNoTodayCard(WidgetTester tester, String nickname) {
  final cards = [for (final card in tester.widgetList<DailyCardSummary>(find.byType(DailyCardSummary))) card.card.profile.nickname];
  must(!cards.contains(nickname), 'B 오늘 탭에 탈퇴한 $nickname 카드가 있음(카드 $cards)');
}

final Map<String, Area1Case> area5CasesTwo = {
  // ── E-WD-05 같은 계정을 두 기기에 ──
  'E-WD-05/A': _session((tester, job) async {
    await arrive(tester, 'home');
    await step('home'); // PC 가 B 에게 같은 계정 토큰을 준다
    await step('ready', timeout: _twoLongWait); // B 가 홈에 닿을 때까지
    await _twoWithdrawA(tester);
    await step('withdrawn', timeout: _twoLongWait);
    return null;
  }),
  'E-WD-05/B': _twoLoginAfter('login', (tester, job) async {
    await arrive(tester, 'home');
    final refresh = Supabase.instance.client.auth.currentSession?.refreshToken;
    must(refresh != null, 'B: 로그인했는데 refresh token 이 없음');
    await step('home');
    final go = await step('tap', timeout: _twoLongWait); // A 가 탈퇴한 뒤 — PC 가 B 가 볼 알림을 준다
    await tap(tester, _tab('나')); // 아무 탭 — 나 탭은 열 때 /me/profile 을 부른다(요청 발생)
    final (login, notice) = await _twoLoginNotice(tester);
    must(login, 'B: 탭을 누른 뒤 02(로그인 화면)로 안 튕김');
    must(notice == go['notice'], 'B: 02 알림 $notice(기대 ${go['notice']})');
    var rejected = false;
    try {
      await Supabase.instance.client.auth.setSession(refresh!);
    } on AuthException {
      rejected = true;
    }
    if (!rejected) await _twoSignOut(); // 다시 들어가졌으면 다음 가설을 위해 지운다
    must(rejected, 'B: 탈퇴 뒤에도 들고 있던 refresh token 으로 다시 로그인됨(기대 거절)');
    return null;
  }),

  // ── E-WD-06 채팅 상대 ──
  'E-WD-06/A': _twoA(),
  'E-WD-06/B': _twoLoginAfter('wait', (tester, job) async {
    final nickname = job['nickname'] as String;
    await _tmConversations(tester);
    must(await _tmEver(tester, _tmRow(nickname), _twoLoadWait), 'B: 대화 목록에 $nickname 방이 없음(기대 있음 — 탈퇴는 나가기가 아니다)');
    await tap(tester, _tmRow(nickname));
    await pumpUntil(tester, find.descendant(of: find.byType(AppBar), matching: find.text(nickname)));
    must(await _tmEver(tester, find.text(_tmGoneNotice), const Duration(seconds: 15)), 'B: 입력칸 자리에 "$_tmGoneNotice" 가 없음');
    final room = find.byType(ChatRoomScreen);
    must(_has(find.descendant(of: room, matching: find.widgetWithText(AppButton, _tmLeave))), 'B: "$_tmLeave" 버튼이 없음');
    must(!_has(find.descendant(of: room, matching: find.byType(ChatInputBar))), 'B: 나간 방에 입력칸이 남음');
    final bubbles = find.descendant(of: room, matching: find.byType(MessageBubble)).evaluate().length;
    must(bubbles == job['count'], 'B: 예전 메시지 $bubbles건(기대 ${job['count']}건 그대로)');
    must(!_has(find.byType(TrustRevealBubble)), 'B: 카톡 아이디 · 실사진 카드가 남음(기대 사라짐)');
    await step('room'); // PC 가 B 토큰으로 보내 409 · left_at · 시스템 줄을 본다
    return null;
  }),

  // ── E-WD-07 오늘 카드 · 받은 수락 ──
  'E-WD-07/A': _twoA(),
  'E-WD-07/B': _twoLoginAfter('wait', (tester, job) async {
    final nickname = job['nickname'] as String;
    await _twoOpenToday(tester);
    _twoNoTodayCard(tester, nickname);
    await tap(tester, _tab('대화'));
    final drawn = find.byWidgetPredicate((w) => w is AcceptanceRow || w is ChatListRow || (w is Text && w.data == _twoChatEmpty));
    if (await appears(tester, drawn, _twoLoadWait) == null) throw E2eBlocked('대화 탭이 $_twoLoadWait 안에 안 그려짐');
    await wait(tester, const Duration(seconds: 1));
    final waiting = [for (final row in tester.widgetList<AcceptanceRow>(find.byType(AcceptanceRow))) row.acceptance.profile.nickname];
    must(!waiting.contains(nickname), 'B 받은 수락에 탈퇴한 $nickname 이 있음(수락 대기 $waiting)');
    return null;
  }),

  // ── E-WD-08 새 카드 후보 ──
  'E-WD-08/A': _twoA(),
  'E-WD-08/B': _twoLoginAfter('wait', (tester, job) async {
    await _twoOpenToday(tester);
    _twoNoTodayCard(tester, job['nickname'] as String);
    return null;
  }),

  // ── E-WD-09 내가 쓴 리뷰 ──
  'E-WD-09/A': _twoA(),
  'E-WD-09/B': _twoLoginAfter('wait', (tester, job) async {
    final nickname = job['nickname'] as String;
    await _openMe(tester);
    final entry = find.text(_twoWrittenEntry);
    await tester.scrollUntilVisible(entry, 300,
        scrollable: find.descendant(of: find.byType(MyProfileScreen), matching: find.byType(Scrollable)).first);
    await tap(tester, entry);
    final page = find.byType(WrittenReviewsScreen);
    await pumpUntil(tester,
        find.descendant(of: page, matching: find.byWidgetPredicate((w) => w is FriendReviewCard || (w is Text && w.data == _twoWrittenEmpty))));
    await wait(tester, const Duration(seconds: 2)); // 들어올 때 다시 읽는다
    final names = [
      for (final card in tester.widgetList<FriendReviewCard>(find.descendant(of: page, matching: find.byType(FriendReviewCard)))) card.review.nickname,
    ];
    must(!names.contains(nickname), 'B 20e 에 탈퇴한 $nickname 줄이 있음(줄 $names)');
    must(_has(find.descendant(of: page, matching: find.text(_twoWrittenEmpty))), 'B 20e 에 "$_twoWrittenEmpty" 가 없음(쓴 리뷰는 A 한 건뿐)');
    return null;
  }),
};
