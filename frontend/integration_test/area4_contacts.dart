part of 'area4.dart';

// 영역 4 SET-29~42 — 연락처 권한 8a/8a-2 · 연락처 고르기 8d · 연락처 차단 관리 16b. B에뮬에서만 돈다.
// PC 쪽은 e2e/area4_contacts.py 의 같은 번호 — 기기 연락처를 넣고 권한을 맞춘 채 앱을 켜고, OS 권한 창은 PC 가 누른다(step 'dialog').
// 화면 글자는 시나리오가 아니라 지금 화면 코드(frontend/lib/safety)에서 옮겼다.

const _permissionAsk = '연락처 접근을 허용해 주세요';
const _permissionOff = '연락처 권한이 꺼져 있어요';
const _pickerTitle = '차단할 연락처 선택';
const _blocksTitle = '연락처 차단';
const _noBlocksTitle = '아직 차단한 연락처가 없어요';
const _noBlocksText = '추가한 연락처 속 지인과는 서로의 카드에 나타나지 않아요.';
const _noMobileNumber = '휴대전화 번호가 있는 연락처만 차단할 수 있어요';
const _formerName = '이전에 차단한 연락처';
const _formerNumber = '이 기기에서 이름을 찾을 수 없어요';

Finder _sheetButton(String label) => find.widgetWithText(SafetySheetButton, label);

List<String> _contactNames(Map<String, dynamic> job) => (job['names'] as List).cast<String>();

/// 16b 에 그려진 줄 수 — 설정 화면은 아래 깔려 가려지므로 16b 안에서만 센다.
int _blockRows() =>
    find.descendant(of: find.byType(ContactBlockListScreen), matching: find.byType(ContactRow)).evaluate().length;

/// 설정 → "연락처 차단" 줄. 권한이 있으면 16b, 없으면 8a 가 뜬다.
Future<void> _tapContactBlocks(WidgetTester tester) async {
  await _openSettings(tester);
  await _reveal(tester, find.text(_blocksTitle));
  await tap(tester, find.text(_blocksTitle));
}

Future<void> _inBlockList(WidgetTester tester) async {
  await _tapContactBlocks(tester);
  await pumpUntil(tester, find.byType(ContactBlockListScreen));
}

/// 16b 줄이 [count] 가 될 때까지(들어올 때마다 새로 읽는다).
Future<void> _waitBlockRows(WidgetTester tester, int count, {Duration timeout = const Duration(seconds: 20)}) async {
  final watch = Stopwatch()..start();
  while (_blockRows() != count) {
    must(watch.elapsed < timeout, '16b 줄이 ${timeout.inSeconds}초 안에 $count 줄이 안 됨(지금 ${_blockRows()}줄)');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 8d 가 열리고 연락처 목록이 읽힐 때까지.
Future<void> _pickerReady(WidgetTester tester, Map<String, dynamic> job) async {
  await pumpUntil(tester, find.byType(ContactPickerScreen));
  await pumpUntil(tester, find.text(_contactNames(job).first));
}

Future<void> _tapAdd(WidgetTester tester) => tap(tester, find.byKey(contactBlockAddKey));

/// 8d 에서 [names] 를 고르고(201명은 목록을 다 굴리지 않고 뷰모델에서 고른다) 버튼 글자 "선택 완료 (N명)" 을 확인한 뒤 누른다.
Future<void> _pick(WidgetTester tester, List<String> names, {bool direct = false}) async {
  if (direct) {
    final container = ProviderScope.containerOf(tester.element(find.byType(ContactPickerScreen)));
    final viewModel = container.read(contactPickerViewModelProvider.notifier);
    for (final contact in container.read(contactPickerViewModelProvider).contacts) {
      if (names.contains(contact.name)) viewModel.toggle(contact.id);
    }
    await tester.pump(const Duration(milliseconds: 300));
  } else {
    for (final name in names) {
      await tap(tester, find.text(name));
    }
  }
  final label = '선택 완료 (${names.length}명)';
  must(button(label).evaluate().isNotEmpty, '버튼 "$label" 이 없음');
  must(enabled(tester, label), '버튼 "$label" 이 눌리지 않음');
  await tap(tester, button(label));
}

/// 권한이 있는 채로 16b 에 들어가 "추가" → 8d 에서 [names] 를 골라 완료한다.
Future<void> _blockViaPicker(WidgetTester tester, Map<String, dynamic> job, List<String> names) async {
  await _tapAdd(tester);
  await _pickerReady(tester, job);
  await _pick(tester, names);
}

/// 8a 시트를 띄운다(권한 없음).
Future<void> _askSheet(WidgetTester tester) async {
  await _tapContactBlocks(tester);
  await pumpUntil(tester, find.text(_permissionAsk));
}

final Map<String, Area1Case> _contactsCases = {
  'E-SET-29': _session((tester, job) async {
    await _askSheet(tester);
    must(_sheetButton('허용하고 계속').evaluate().isNotEmpty, '"허용하고 계속" 이 없음');
    must(_sheetButton('나중에 할게요').evaluate().isNotEmpty, '"나중에 할게요" 가 없음');
    must(find.byType(ContactPickerScreen).evaluate().isEmpty && find.byType(ContactBlockListScreen).evaluate().isEmpty, '8a 보다 먼저 다른 화면이 열림');
    return null;
  }),
  'E-SET-30': _session((tester, job) async {
    await _askSheet(tester);
    await tap(tester, _sheetButton('허용하고 계속'));
    await step('dialog'); // PC 가 OS 권한 창의 "허용" 을 누른다
    await pumpUntil(tester, _screenTitle(_pickerTitle));
    for (final name in _contactNames(job)) {
      await pumpUntil(tester, find.text(name));
    }
    return null;
  }),
  // 설정 앱이 앞으로 와 앱이 멈춘다(paused) — 눌러 놓고 바로 끝내고, 설정 앱이 맨 위인지는 PC 가 본다.
  'E-SET-31': _session((tester, job) async {
    await _askSheet(tester);
    await tap(tester, _sheetButton('나중에 할게요'));
    await pumpUntil(tester, find.text(_permissionOff));
    await tester.ensureVisible(_sheetButton('기기 설정 열기'));
    await tester.pump();
    await tester.tap(_sheetButton('기기 설정 열기'));
    return null;
  }),
  'E-SET-32': _session((tester, job) async {
    await _askSheet(tester);
    await tap(tester, _sheetButton('허용하고 계속'));
    await step('dialog'); // PC 가 "허용 안 함" 을 누른다
    await pumpUntil(tester, find.text(_permissionOff));
    must(find.text(_permissionOff).evaluate().length == 1, '8a-2 시트가 ${find.text(_permissionOff).evaluate().length}개');
    return null;
  }),
  'E-SET-33': _session((tester, job) async {
    await _tapContactBlocks(tester);
    await pumpUntil(tester, _screenTitle(_blocksTitle));
    must(find.text(_permissionAsk).evaluate().isEmpty, '권한이 있는데 8a 시트가 뜸');
    return null;
  }),
  'E-SET-34': _session((tester, job) async {
    await _inBlockList(tester);
    await pumpUntil(tester, find.text(_noBlocksTitle));
    must(find.text(_noBlocksText).evaluate().isNotEmpty, '빈 화면 설명 "$_noBlocksText" 없음');
    return null;
  }),
  'E-SET-35': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockViaPicker(tester, job, _contactNames(job).take(job['pick'] as int).toList());
    await _waitBlockRows(tester, job['pick'] as int);
    for (final name in _contactNames(job).take(job['pick'] as int)) {
      must(find.descendant(of: find.byType(ContactBlockListScreen), matching: find.text(name)).evaluate().isNotEmpty, '16b 에 "$name" 줄이 없음');
    }
    return null;
  }),
  'E-SET-36': _session((tester, job) async {
    await _inBlockList(tester);
    await _tapAdd(tester);
    await _pickerReady(tester, job);
    must(button('선택 완료 (0명)').evaluate().isNotEmpty, '"선택 완료 (0명)" 이 없음');
    must(!enabled(tester, '선택 완료 (0명)'), '아무도 안 골랐는데 버튼이 눌림');
    return null;
  }),
  'E-SET-37': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockViaPicker(tester, job, _contactNames(job));
    await pumpUntil(tester, find.text(_noMobileNumber), timeout: const Duration(seconds: 15));
    must(find.byType(ContactPickerScreen).evaluate().isNotEmpty, '유선 번호만 골랐는데 8d 가 닫힘');
    return null;
  }),
  'E-SET-38': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockViaPicker(tester, job, _contactNames(job));
    await _waitBlockRows(tester, 1);
    return null;
  }),
  'E-SET-39': _session((tester, job) async {
    await _inBlockList(tester);
    await _tapAdd(tester);
    await _pickerReady(tester, job);
    await _pick(tester, _contactNames(job), direct: true);
    // 200 + 1 로 나눠 보낸 뒤 8d 가 닫히면 오류 없이 끝난 것이다(오류면 닫히지 않는다). 행 수는 PC 가 DB 에서 센다.
    final watch = Stopwatch()..start();
    while (find.byType(ContactPickerScreen).evaluate().isNotEmpty) {
      must(watch.elapsed < const Duration(seconds: 90), '201명 차단 뒤 90초가 지나도 8d 가 안 닫힘');
      await tester.pump(const Duration(milliseconds: 200));
    }
    return {'note': '201명 차단 ${watch.elapsed.inSeconds}초'};
  }),
  // 시나리오: 기기에서 연락처를 지우면 16b 가 "이전에 차단한 연락처" 로 보인다. 앱은 이름표를 차단할 때 앱 파일에 저장해 두고
  // 16b 가 그것만 읽으므로(contact_name_store.dart) 이름이 그대로 남는다. 제품 동작 결정이라 fail 이 아니라 known 으로 알린다
  // (대장 10-05: 시나리오 줄은 고치지 않고, 사용자 최종 확인 때 묻는다).
  'E-SET-40': _session((tester, job) async {
    final names = _contactNames(job).take(job['pick'] as int).toList();
    await _inBlockList(tester);
    await _blockViaPicker(tester, job, names);
    await _waitBlockRows(tester, names.length);
    await step('delete'); // PC 가 기기에서 첫 연락처를 지운다
    await tap(tester, find.byType(BackButton).first);
    await pumpUntil(tester, find.text(_blocksTitle));
    await tap(tester, find.text(_blocksTitle));
    await _waitBlockRows(tester, names.length);
    final former = find.text(_formerName).evaluate().length;
    final formerNumber = find.text(_formerNumber).evaluate().length;
    if (former == 1 && formerNumber == 1) return null; // 시나리오대로
    return {
      'known': '앱은 이름표를 앱 파일에 저장해 16b 가 그것만 읽음 → 기기 연락처를 지워도 "$_formerName"로 안 바뀜 '
          '(줄 $former개 · 안내 $formerNumber개)',
    };
  }),
  'E-SET-41': _session((tester, job) async {
    final names = _contactNames(job).take(job['pick'] as int).toList();
    await _inBlockList(tester);
    await _blockViaPicker(tester, job, names);
    await _waitBlockRows(tester, names.length);
    await tap(tester, find.descendant(of: find.byType(ContactRow), matching: find.byType(IconButton)).first);
    await pumpUntil(tester, find.text('차단을 해제할까요?'));
    must(find.text('이 연락처가 다시 카드에 나타날 수 있어요.').evaluate().isNotEmpty, '해제 시트 설명이 없음');
    await tap(tester, _sheetButton('해제'));
    await _waitBlockRows(tester, names.length - 1);
    return null;
  }),
  'E-SET-42': _session((tester, job) async {
    final names = _contactNames(job);
    final first = names.take(job['pick'] as int).toList();
    await _inBlockList(tester);
    await _blockViaPicker(tester, job, first);
    await _waitBlockRows(tester, first.length);
    await _blockViaPicker(tester, job, names.skip(first.length).take(job['add'] as int).toList());
    await _waitBlockRows(tester, first.length + (job['add'] as int));
    return null;
  }),
};
