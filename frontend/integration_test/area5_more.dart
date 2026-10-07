part of 'area5.dart';

// 영역 5 E-ME-05 · 22 · 32. PC 쪽은 e2e/area5_more.py 의 같은 번호 — 05 는 두 기기(열쇠 `E-ME-05/A` 폰 · `E-ME-05/B` 에뮬), 22 · 32 는 한 기기.
// 이 파일의 이름은 모두 `_more` 로 시작한다 — 같은 라이브러리의 다른 area5 파일과 이름이 겹치지 않게.
// 이 파일은 `flutter analyze` 만 돌렸고 기기에서는 아직 안 돌려 봤다.

const _morePeer = Duration(minutes: 8); // 상대 기기 · PC 가 일을 끝내기를 기다리는 멈춤

/// 카드 [ProfileCard] 안의 글자 전부(위에서 아래로). 15-4 와 10b 가 같은 위젯을 쓰므로 두 화면의 이 목록이 같아야 한다.
List<String> _moreCardTexts(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.descendant(of: find.byType(ProfileCard), matching: find.byType(Text))))
        if ((text.data ?? '').isNotEmpty) text.data!,
    ];

/// 글자 목록을 PC 에 실어 보내고 PC 가 비교를 마치기를 기다린다 — `step` 은 값을 못 실어 `say` · `hear` 를 직접 부른다.
Future<void> _moreSayTexts(WidgetTester tester, String name) async {
  await say({'step': name, 'texts': _moreCardTexts(tester)});
  await hear(timeout: _morePeer);
}

final Map<String, Area1Case> area5CasesMore = {
  // A: 나 탭 → "남이 보는 내 프로필 카드"(15-4) 의 카드 글자를 PC 에 말한다.
  'E-ME-05/A': _session((tester, job) async {
    await _openMe(tester);
    await tap(tester, _entry(_previewEntry));
    await pumpUntil(tester, find.byType(ProfileCard));
    await wait(tester, const Duration(seconds: 1)); // 카드 안쪽이 다 그려지게
    await _moreSayTexts(tester, 'card');
    return null;
  }),
  // B: 오늘 탭 → A 가 대상인 카드 한 장 → 카드 상세(10b) 의 카드 글자를 PC 에 말한다. PC 가 A 의 글자와 맞대 본다.
  'E-ME-05/B': _session((tester, job) async {
    await arrive(tester, 'home');
    await tap(tester, _tab('오늘'));
    await pumpUntil(tester, find.byType(DailyCardSummary), timeout: const Duration(seconds: 30));
    await tap(tester, find.byType(DailyCardSummary));
    await pumpUntil(tester, find.byType(ProfileCard), timeout: const Duration(seconds: 15));
    await wait(tester, const Duration(seconds: 1));
    await _moreSayTexts(tester, 'card');
    return null;
  }),
  // 15c 에서 자기소개를 새 글로 고치고 → PC 가 에뮬 망을 느리게 → "저장" 을 누르자마자 시스템 뒤로 → 15-5 가 새 글을 보인다(저장은 화면을 나가도 끝까지 된다).
  'E-ME-22': _session((tester, job) async {
    final tag = job['tag'] as String;
    await _openManage(tester);
    await _actEnterBio(tester);
    await type(tester, find.byType(TextField).first, job['bio'] as String);
    await step('slow');
    await tap(tester, button(_actSave));
    await tester.binding.handlePopRoute(); // 저장 응답이 오기 전에 시스템 뒤로
    final title = await _actUntilTitle(tester, _actManageTitle, timeout: const Duration(seconds: 60));
    final shown = await _actUntil(tester, () => _has(find.textContaining(tag)), timeout: const Duration(seconds: 120));
    return {'title': title, 'manage_bios': shown ? _actTextsWith(tester, find.byType(ProfileManageScreen), tag) : <String>[]};
  }),
  // 15-6 에 다른 사람이 쓰는 닉네임을 친다 → "이미 있는 닉네임이에요" 와 저장 꺼짐, 또는 저장을 눌러도 서버가 막아 그 문구가 뜨고 15-6 에 머문다.
  'E-ME-32': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    final probe = await _actProbeNickname(tester, job['nickname'] as String);
    var afterSave = false;
    if (probe['taken'] != true && probe['save_enabled'] == true) {
      await tap(tester, button(_actSave)); // 확인이 막지 않았으면 저장 뒤 서버(409)가 막아야 한다
      afterSave = (await appears(tester, find.text(_actNicknameTaken), const Duration(seconds: 10))) != null;
    }
    return {
      'taken': probe['taken'],
      'save_enabled': probe['save_enabled'],
      'after_save_taken': afterSave,
      'on_edit': _has(find.byType(BasicInfoEditScreen)),
    };
  }),
};
