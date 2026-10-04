part of 'area4.dart';

// 영역 3 SAFE-35~46 — 연락처 차단(8a · 8a-2 · 8d · 16b). B에뮬에서만 돈다.
// PC 쪽은 e2e/area3_contacts.py 의 같은 번호 — 연락처를 넣고 권한을 맞춘 채 앱을 켜고, OS 권한 창 · 서버 확인은 PC 가 한다.
// 화면을 여는 도우미(_inBlockList · _blockViaPicker · _pick · _waitBlockRows)는 영역 4 연락처(area4_contacts.dart)의 것을 그대로 쓴다.
// 이 파일이 area4.dart 의 part 인 이유: 그 도우미들이 그 라이브러리의 비공개 이름이라 area3.dart 의 part 로는 안 보인다.

List<String> _pickNames(Map<String, dynamic> job) => (job['pick_names'] as List).cast<String>();

/// "나중에 할게요" 나 OS 창 거부 뒤에 뜬 8a-2 에서 "기기 설정 열기" 를 누른다. 설정 앱이 앞으로 와 앱이 멈추므로 누르고 바로 끝낸다.
Future<void> _openDeviceSettings(WidgetTester tester) async {
  await pumpUntil(tester, find.text(_permissionOff));
  await tester.ensureVisible(_sheetButton('기기 설정 열기'));
  await tester.pump();
  await tester.tap(_sheetButton('기기 설정 열기'));
}

/// 16b 에서 [names] 를 8d 로 골라 차단하고 [rows] 줄이 될 때까지. rows 가 0 이면 휴대전화가 없어 안내 문구가 뜨는지.
Future<void> _blockAndWait(WidgetTester tester, Map<String, dynamic> job) async {
  final rows = job['rows'] as int;
  await _blockViaPicker(tester, job, _pickNames(job));
  if (rows == 0) {
    await pumpUntil(tester, find.text(_noMobileNumber), timeout: const Duration(seconds: 15));
  } else {
    await _waitBlockRows(tester, rows);
  }
}

final Map<String, Area1Case> _safeContactsCases = {
  // 처음 열면 8a 안내 → 허용하고 계속 → OS 창 허용(PC) → 8d 에 연락처 3명.
  'E-SAFE-35': _contactsCases['E-SET-30']!,
  // 두 판: 나중에 할게요 / OS 창 허용 안 함 — 둘 다 8a-2, 설정 열기 뒤 설정 앱이 맨 위(PC 가 본다).
  'E-SAFE-36': _session((tester, job) async {
    await _askSheet(tester);
    if (job['phase'] == 'later') {
      await tap(tester, _sheetButton('나중에 할게요'));
    } else {
      await tap(tester, _sheetButton('허용하고 계속'));
      await step('dialog'); // PC 가 OS 권한 창의 "허용 안 함" 을 누른다
    }
    await _openDeviceSettings(tester);
    return null;
  }),
  // 이름 · 가린 번호가 16b 에 보인다. 서버에 번호 원문이 없는지는 PC 가 DB 에서 본다.
  'E-SAFE-37': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockAndWait(tester, job);
    final name = _pickNames(job).first;
    must(find.descendant(of: find.byType(ContactBlockListScreen), matching: find.text(name)).evaluate().isNotEmpty, '16b 에 "$name" 줄이 없음');
    must(find.descendant(of: find.byType(ContactBlockListScreen), matching: find.textContaining('****')).evaluate().isNotEmpty,
        '16b 에 가린 번호(****)가 없음');
    return null;
  }),
  // 38 · 39 — 앱은 차단까지만, 양방향 후보는 PC 가 서버에서 본다.
  'E-SAFE-38': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockAndWait(tester, job);
    return null;
  }),
  'E-SAFE-39': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockAndWait(tester, job);
    return null;
  }),
  'E-SAFE-40': _contactsCases['E-SET-37']!,
  // 한 사람에 번호 둘 → 16b 두 줄(이름은 같다).
  'E-SAFE-41': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockAndWait(tester, job);
    return null;
  }),
  // 같은 사람을 또 막아도 한 줄 — 첫 차단 뒤 PC 가 id 를 적어 두고(step), 둘째 차단 뒤 같은 id 인지 본다.
  'E-SAFE-42': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockAndWait(tester, job);
    await step('first');
    // 16b 에 같은 이름 줄이 이미 있어, 8d 로 넘어가는 사이 이름 글자만 찾으면 16b 것으로 통과해 버린다 — 8d 안의 이름을 기다린다.
    await _tapAdd(tester);
    await pumpUntil(tester, find.byType(ContactPickerScreen));
    await pumpUntil(tester, find.descendant(of: find.byType(ContactPickerScreen), matching: find.text(_pickNames(job).first)));
    await _pick(tester, _pickNames(job));
    await wait(tester, const Duration(seconds: 3)); // 다시 읽은 목록이 자리 잡을 때까지
    await _waitBlockRows(tester, 1);
    must(_blockRows() == 1, '같은 사람을 또 막았더니 16b 가 ${_blockRows()}줄');
    return null;
  }),
  'E-SAFE-43': _contactsCases['E-SET-39']!,
  // 막은 뒤(PC 가 서로 후보에서 빠진 것을 확인) 16b 휴지통 → 시트 → 해제 → 줄이 사라지고 빈 화면.
  'E-SAFE-45': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockAndWait(tester, job);
    await step('blocked');
    await tap(tester, find.descendant(of: find.byType(ContactRow), matching: find.byType(IconButton)).first);
    await pumpUntil(tester, find.text('차단을 해제할까요?'));
    await tap(tester, _sheetButton('해제'));
    await _waitBlockRows(tester, 0);
    await pumpUntil(tester, find.text(_noBlocksTitle));
    return null;
  }),
  // 차단하고 끝(phase block) → PC 가 앱을 지우고 다시 깐다 → 새로 로그인(phase after)해 16b 를 연다 — 이름표 파일이 없어 이름 없는 줄.
  'E-SAFE-46': _session((tester, job) async {
    if (job['phase'] == 'block') {
      await _inBlockList(tester);
      await _blockAndWait(tester, job);
      return null;
    }
    await _inBlockList(tester);
    await _waitBlockRows(tester, 1);
    must(find.text(_formerName).evaluate().length == 1, '"$_formerName" 줄이 ${find.text(_formerName).evaluate().length}개(기대 1)');
    must(find.text(_formerNumber).evaluate().length == 1, '"$_formerNumber" 가 1줄이 아님');
    return null;
  }),
};
