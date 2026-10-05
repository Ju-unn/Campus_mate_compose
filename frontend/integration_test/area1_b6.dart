part of 'area1.dart';

// 영역 1 묶음 6 — 두 기기가 같이 하는 것(E-ONB-05)과 에뮬 네트워크(E-ONB-74).
// PC 쪽은 e2e/area1_b6.py 의 같은 번호 — 계정 · 네트워크 · 두 기기 맞추기는 PC 가 하고, 앱은 멈춰 서서(step) 기다린다.

/// 누른 뒤 결과가 보일 때까지 — 저장되면 04-1b, 닉네임이 겹치면 04-1 에 "이미 있는 닉네임이에요".
const _afterNext = Duration(seconds: 20);

final Map<String, Area1Case> _b6Cases = {
  // 같은 닉네임을 채우고 멈춤 → PC 가 두 기기를 같이 보냄 → 다음 → 저장(04-1b) 아니면 거절(04-1 + 문구).
  'E-ONB-05': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _fillBasics(tester, nickname: job['nickname'] as String);
    await step('typed');
    await tap(tester, button('다음'));
    final watch = Stopwatch()..start();
    while (watch.elapsed < _afterNext) {
      if (screen('04-1b').evaluate().isNotEmpty) return {'outcome': 'saved', 'note': '저장 ${watch.elapsedMilliseconds}ms'};
      // 두 앱 모두 누르기 전엔 닉네임이 "사용할 수 있어요" 였고 "이미 있는 닉네임이에요" 는 서버 409 뒤에만 뜬다(버튼 위 오류 줄).
      // 닉네임 칸 아래의 초록 문구는 409 뒤에도 그대로 남으므로(뷰모델이 nicknameCheck 를 안 바꾼다) 그 부재는 조건이 아니다.
      if (screen('04-1').evaluate().isNotEmpty && find.text(_nicknameTaken).evaluate().isNotEmpty) {
        return {'outcome': 'taken', 'note': '거절 ${watch.elapsedMilliseconds}ms'};
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    throw TestFailure('다음을 누르고 ${_afterNext.inSeconds}초 안에 저장도 거절도 안 보임 — 지금 보이는 것: ${_whereNow()}');
  }),
  // 06-3 → 20 에서 코드를 넣고 멈춤 → PC 가 네트워크를 끔 → 확인 → 문구, 20 에 머묾.
  'E-ONB-74': _session((tester, job) async {
    await _toReferral(tester);
    await type(tester, _codeField, job['code'] as String);
    await step('typed');
    await tap(tester, _confirmCode);
    final shown = await appears(tester, find.text(_networkDown), const Duration(seconds: 20));
    must(shown != null, '네트워크가 끊겼는데 20초 안에 "$_networkDown" 가 안 뜸');
    must(screen('20').evaluate().isNotEmpty, '네트워크 오류 뒤 20 을 벗어남');
    return {'note': '문구까지 ${shown!.inMilliseconds}ms'};
  }),
};
