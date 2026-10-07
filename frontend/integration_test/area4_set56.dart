part of 'area4.dart';

// 영역 4 E-SET-56 — 설정 "지원" 카드. PC 쪽은 e2e/area4_set56.py. 줄 순서를 보고 이용약관 · 개인정보처리방침 줄을 차례로 누른다.
// 누르면 기기 브라우저가 맨 앞으로 와 앱 프레임이 멎으므로 누르자마자 [step] 으로 PC 에게 넘긴다(맨 앞 앱은 PC 가 dumpsys 로 보고 앱을 다시 앞으로 부른다).
// 이 파일은 `flutter analyze` 만 돌렸고 기기에서는 아직 안 돌려 봤다.

const _supportOrder = ['자주 묻는 질문', '이용약관', '개인정보처리방침', '로그아웃'];

final Map<String, Area1Case> _set56Cases = {
  'E-SET-56': _session((tester, job) async {
    await _openSettings(tester);
    await pumpUntil(tester, find.text('자주 묻는 질문'));
    var previous = -1.0;
    for (final row in _supportOrder) {
      await _reveal(tester, find.text(row));
      final y = tester.getTopLeft(find.text(row).first).dy + _list(tester).position.pixels;
      must(y > previous, '"지원" 카드 순서가 어긋남: $row 가 앞 줄보다 위에 있음');
      previous = y;
    }
    await _reveal(tester, find.text('이용약관'));
    await tester.tap(find.text('이용약관'));
    await step('terms');
    await pumpUntil(tester, find.text('개인정보처리방침'), timeout: const Duration(seconds: 20));
    must(find.text('이용약관').evaluate().isNotEmpty, '브라우저에 다녀온 뒤 설정 화면에 안 남음');
    await tester.tap(find.text('개인정보처리방침'));
    await step('privacy');
    await pumpUntil(tester, find.text('개인정보처리방침'), timeout: const Duration(seconds: 20));
    return null;
  }),
};
