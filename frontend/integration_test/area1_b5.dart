part of 'area1.dart';

// 영역 1 묶음 5 — 학생증 검토 이후(3b 대기 화면 · 통과 · 알림) · 재부팅.
// PC 쪽은 e2e/area1_b5.py 의 같은 번호 — API 로 사람 검토 대기 계정을 만들고, 앱은 3b 대기 화면에서 확인한다.
// 통과 · 반려 처리와 알림 읽기는 PC 가 한다(앱이 step 에서 멈춘 사이).

/// 3b 대기 화면("조금 더 확인이 필요해요")이 [within] 안에 뜨고 실명 칸 · 제출 버튼이 없다.
/// [noLogin] 이면(다시 켠 경우) 그동안 로그인 화면이 한 번도 안 보여야 한다. 걸린 시간을 돌려준다.
Future<Duration> _heldScreen(WidgetTester tester, {Duration within = const Duration(seconds: 30), bool noLogin = false}) async {
  final watch = Stopwatch()..start();
  var sawLogin = false;
  while (watch.elapsed < within && find.text(_held).evaluate().isEmpty) {
    await tester.pump(const Duration(milliseconds: 100));
    sawLogin |= screen('login').evaluate().isNotEmpty;
  }
  must(find.text(_held).evaluate().isNotEmpty, '${within.inSeconds}초 안에 대기 화면 "$_held" 가 안 나옴 — 지금 보이는 것: ${_whereNow()}');
  must(!noLogin || !sawLogin, '다시 켰는데 로그인 화면이 나옴');
  must(_realNameField.evaluate().isEmpty, '대기 화면에 실명 칸이 남음');
  must(_proofForm.evaluate().isEmpty, '대기 화면에 "$_submitProof" 가 보임');
  return watch.elapsed;
}

/// step 이 끝난 때부터 35초 — 대기 화면의 상태 조회는 30초 주기다(student_verification_screen.dart:19, E-GATE-44 와 같은 근거).
const _afterReview = Duration(seconds: 35);

final Map<String, Area1Case> _b5Cases = {
  // 첫 켬(로그인)과 다시 켬 둘 다 대기 화면이다 — 다시 켠 쪽은 로그인 화면 0번, 제출 폼 0.
  'E-GATE-39': _session((tester, job) async {
    final again = !_fresh(job);
    final took = await _heldScreen(tester, within: Duration(seconds: again ? 15 : 30), noLogin: again);
    return {'note': '${again ? '다시 켠 뒤' : '첫 켬'} 대기 화면까지 ${took.inMilliseconds}ms'};
  }),
  // 대기 화면에서 멈춤 → PC 가 SUPABASE §7 순서로 통과 처리 → 35초 안에 3c.
  'E-GATE-41': _session((tester, job) async {
    await _heldScreen(tester);
    await step('waiting');
    final took = await appears(tester, screen('3c'), _afterReview);
    must(took != null, '통과 처리 뒤 ${_afterReview.inSeconds}초 안에 3c 로 안 넘어감 — 지금 보이는 것: ${_whereNow()}');
    return {'note': '통과 처리 뒤 ${took!.inMilliseconds}ms'};
  }),
  // 대기 화면에서 멈춤 → PC 가 앱을 뒤로 두고 처리 · 알림을 읽고 누름 → 통과면 3c, 반려면 배너 + 제출 폼.
  'E-GATE-43': _session((tester, job) async {
    await _heldScreen(tester);
    await step('waiting');
    if (job['verdict'] == 'approved') {
      final took = await appears(tester, screen('3c'), _afterReview);
      must(took != null, '통과 알림 뒤 ${_afterReview.inSeconds}초 안에 3c 로 안 넘어감 — 지금 보이는 것: ${_whereNow()}');
      return {'note': '통과 → 3c ${took!.inMilliseconds}ms'};
    }
    final back = await appears(tester, find.textContaining(_rejectReason), _afterReview);
    must(back != null, '반려 알림 뒤 ${_afterReview.inSeconds}초 안에 배너 "$_rejectReason" 가 안 나옴 — 지금 보이는 것: ${_whereNow()}');
    must(_proofForm.evaluate().isNotEmpty, '배너는 떴는데 제출 폼이 없음');
    return {'note': '반려 → 배너 ${back!.inMilliseconds}ms'};
  }),
  // 로그인 → (PC 가 재부팅) → 다시 켠 앱이 로그인 화면 없이 홈.
  'E-AUTH-18': _session((tester, job) async {
    if (job['phase'] == 'login') {
      await arrive(tester, 'home');
      return null;
    }
    return _arriveAt(tester, job);
  }),
};
