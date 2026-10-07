part of 'area1.dart';

// 영역 3 E-REV-41 두 기기(A=폰 추천인 · B=에뮬 가입하는 친구). PC 쪽은 e2e/area3_phone9.py two_41 — 열쇠는 `E-REV-41/A` · `/B`, 두 앱이 서로 기다리는 순서는 PC 가 `step` 에서 잇는다.
// 온보딩 20 도우미(_toReferral · _codeField · _confirmCode · _closeReviewSheet)가 area1_b2.dart 에 있어 이 파일은 area1 의 part 다.
// 알림 읽기 · 1건 확인 · 누르기는 PC, 두 20b 시트의 상대가 맞는지는 앱이 must 로 본다(twodev 는 앱이 말한 값을 PC 판정에 돌려주지 않는다).
// 이 파일은 `flutter analyze` 만 통과했고 기기에서는 아직 안 돌려 봤다.

const _rev41Wait = Duration(minutes: 9); // A 가 B 의 온보딩 · 코드 · 알림 · 누르기를 기다리는 멈춤(PC side_timeout A 600초 안)
const _rev41SheetWait = Duration(seconds: 30); // 눌린 뒤 앱이 앞으로 와 20b 를 띄우는 시간
const _rev41Confirmed = Duration(seconds: 5); // 시나리오 "코드 확인 직후 20b"

/// 지금 뜬 20b 시트의 상대 id — [within] 안에 안 뜨면 [what] 으로 실패.
Future<String> _rev41Sheet(WidgetTester tester, Duration within, String what) async {
  final sheet = find.byType(FriendReviewComposeSheet);
  must(await appears(tester, sheet, within) != null, what);
  return tester.widget<FriendReviewComposeSheet>(sheet.first).revieweeId;
}

final Map<String, Area1Case> area3Cases9 = {
  // A — 홈까지 가서 알림 토큰이 올라가게 두고 멈춘다. PC 가 HOME · B 를 기다림 · 알림 1건 확인 · 누름을 한 뒤 go 의 tapped 로 알려 준다.
  'E-REV-41/A': _session((tester, job) async {
    await arrive(tester, 'home');
    await wait(tester, const Duration(seconds: 3));
    final go = await step('holding', timeout: _rev41Wait);
    if (go['tapped'] != true) return null; // 알림이 안 왔다 — 판정은 PC 가 이미 했다
    final friend = job['friend_id'] as String;
    final reviewee = await _rev41Sheet(tester, _rev41SheetWait, 'A: 알림을 눌렀는데 20b 시트가 안 뜸');
    must(reviewee == friend, 'A: 20b 상대 $reviewee(기대 B $friend)');
    final location = GoRouter.of(tester.element(find.byType(FriendReviewComposeSheet).first)).routerDelegate.currentConfiguration.uri.path;
    must(location == '${AppRoutes.friendReviewWrite}/$friend', 'A: 경로 $location(기대 ${AppRoutes.friendReviewWrite}/$friend)');
    return {'location': location};
  }),
  // B — 06-3 → 20 에서 멈췄다가(PC 가 A 준비를 기다림) A 의 코드를 넣고 확인 → 5초 안 20b(A 에게 쓰기) → 닫으면 20d.
  'E-REV-41/B': _session((tester, job) async {
    await _toReferral(tester);
    await step('code', timeout: _rev41Wait);
    await type(tester, _codeField, job['code'] as String);
    await tap(tester, _confirmCode);
    final referrer = job['referrer_id'] as String;
    final reviewee = await _rev41Sheet(tester, _rev41Confirmed, 'B: 코드 확인 뒤 5초 안에 20b 시트가 안 뜸');
    must(reviewee == referrer, 'B: 20b 상대 $reviewee(기대 A $referrer)');
    await _closeReviewSheet(tester); // 닫으면 20d
    await step('redeemed');
    return null;
  }),
};
