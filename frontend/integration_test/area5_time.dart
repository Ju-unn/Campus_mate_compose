part of 'area5.dart';

// 영역 5 시간조작 2개(묶음 area5-time — E-WD-10 · 11). PC 쪽은 e2e/area5_time.py 의 같은 번호 — 계정 · 방을 만들고, A 를 API 로 탈퇴시키고,
// 관문을 지나 배치(chat-gate · cleanup)를 부른 뒤 DB 를 본다. 폰은 남는 쪽 B 이고 배치가 끝난 뒤 로그인해 본 것만 Map 으로 말한다(판정은 PC).
// 화면 글자 · 위젯은 지금 화면 코드(chat_room_screen.dart _PartnerGoneNotice · conversations_screen.dart · chat_list_row.dart)에서 옮겼다.
// 이 파일의 이름은 모두 `_tm` 으로 시작한다. 탈퇴 · 나가기 버튼은 누르지 않는다("채팅방 나가기" 는 있는지만 본다).
// 이 파일은 클라우드 세션에서 Flutter 없이 썼다 — `flutter analyze` · 기기 실행은 아직이다.

const _tmGoneNotice = '상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.'; // chat_room_screen.dart _PartnerGoneNotice
const _tmLeave = '채팅방 나가기'; // 같은 곳 AppButton
const _tmListWait = Duration(seconds: 30); // 로그인 · 목록 조회 · 첫 그림(area3_b5.dart 와 같다)

/// 대화 목록의 [nickname] 줄.
Finder _tmRow(String nickname) => find.byWidgetPredicate((w) => w is ChatListRow && w.conversation.partner.nickname == nickname);

/// 홈 → 아래 탭 "대화"(13).
Future<void> _tmConversations(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('대화'));
  await pumpUntil(tester, find.byType(ConversationsScreen), timeout: const Duration(seconds: 15));
}

/// [within] 안에 [finder] 가 한 번이라도 보였는지.
Future<bool> _tmEver(WidgetTester tester, Finder finder, Duration within) async => await appears(tester, finder, within) != null;

final Map<String, Area1Case> area5CasesTime = {
  // 배치 뒤 B 가 그 방을 연다 — 목록에 방이 없으면 room=false 로 끝낸다. 방이 열리면 입력칸 자리(나간 방 안내 · 나가기 버튼 · 입력칸)를 읽는다.
  'E-WD-10': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _tmConversations(tester);
    if (!await _tmEver(tester, _tmRow(nickname), _tmListWait)) {
      return {'room': false, 'gone_notice': null, 'leave_button': null, 'input': null};
    }
    await tap(tester, _tmRow(nickname));
    await pumpUntil(tester, find.descendant(of: find.byType(AppBar), matching: find.text(nickname)));
    final notice = await _tmEver(tester, find.text(_tmGoneNotice), const Duration(seconds: 15));
    final room = find.byType(ChatRoomScreen);
    return {
      'room': true,
      'gone_notice': notice,
      'leave_button': _has(find.descendant(of: room, matching: find.widgetWithText(AppButton, _tmLeave))),
      'input': _has(find.descendant(of: room, matching: find.byType(ChatInputBar))),
    };
  }),
  // 정리 배치 뒤 B 가 대화 목록을 연다 — 닫히지 않는 다른 방(control) 줄이 뜰 때까지 기다린 뒤 목록 줄의 닉네임을 모두 말한다(그 방이 있는지는 PC 가 가린다).
  'E-WD-11': _session((tester, job) async {
    await _tmConversations(tester);
    final drawn = await _tmEver(tester, _tmRow(job['control'] as String), _tmListWait);
    if (drawn) await wait(tester, const Duration(seconds: 2)); // 목록을 다시 읽는 사이의 빈 순간이 아닌지
    final rows = [for (final row in tester.widgetList<ChatListRow>(find.byType(ChatListRow))) row.conversation.partner.nickname];
    // job['nickname'] 은 PC 가 판정에 쓴다 — 앱은 목록 전체를 말할 뿐 고르지 않는다
    return {'waited': drawn, 'rows': rows, 'looked_for': job['nickname']};
  }),
};
