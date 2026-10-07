part of 'area1.dart';

// 영역 4 E-SET-57 — 02-c 이용약관 "보기". PC 쪽은 e2e/area4_terms.py. 누르면 기기 브라우저가 맨 앞으로 와 앱 프레임이 멎으므로
// 누르자마자 [step] 으로 PC 에게 넘긴다(PC 가 브라우저 화면 글자를 읽고 앱을 다시 앞으로 부른다). 이 파일은 `flutter analyze` 만 돌렸고 기기에서는 아직 안 돌려 봤다.

final Map<String, Area1Case> _termsCases = {
  'E-SET-57': _session((tester, job) async {
    await arrive(tester, 'consent');
    final view = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '이용약관 보기');
    await tester.ensureVisible(view);
    await tester.pump();
    await tester.tap(view);
    await step('terms');
    await arrive(tester, 'consent');
    return null;
  }),
};
