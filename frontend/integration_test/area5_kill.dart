part of 'area5.dart';

// 영역 5 아바타를 만드는 중 앱을 죽이는 가설 둘(묶음 area5-kill — 폰 A: E-EDGE-17 · 18). PC 쪽은 e2e/area5_kill.py 의 같은 번호.
// phase press: 15b 시트에서 "10 쓰고 만들기" 를 누르자마자 답을 안 기다리는 멈춤 말(`pressed`)을 보내면 PC 가 2초 뒤 프로세스를 죽인다(안 죽으면 30초 뒤 끝난다).
// phase after: 저장된 세션 그대로 다시 켜 — 17 은 새 그림 · 줄어든 하트를 읽고, 18 은 15 를 연 채 멈춘 뒤(PC 가 첫 시도가 아직 만드는 중인지 본다) 다시 누르고 끝까지 기다린다.
// 이 파일의 이름은 모두 `_kl` 로 시작한다. 이 파일은 기기에서 아직 안 돌려 봤다.

/// 17 다시 켠 앱 — 히어로 그림이 그려지길 기다려 그 파일 이름과 15b 시트의 하트 줄을 말한다(시트는 닫기만 한다 — 만들기 · 충전은 안 누른다).
Future<Map<String, Object?>> _klReread(WidgetTester tester) async {
  await _openMe(tester);
  await _actUntil(tester, () => _avatarFile(tester) != null);
  final file = _avatarFile(tester);
  await _photoOpenSheet(tester);
  return {'avatar_file': file, 'sheet_body': _photoLine(_photoSheetTexts(tester), _heartLine)};
}

final Map<String, Area1Case> area5CasesKill = {
  'E-EDGE-17': (tester, job) async {
    if (job['phase'] == 'after') return _klReread(tester);
    return _klPress(tester, job);
  },
  'E-EDGE-18': (tester, job) async {
    if (job['phase'] != 'after') return _klPress(tester, job);
    await _openMe(tester);
    await step('opened'); // PC 가 첫 시도가 아직 만드는 중인지 본다
    await _photoOpenSheet(tester);
    final texts = _photoSheetTexts(tester);
    return {'sheet_body': _photoLine(texts, _heartLine), ...await _photoRegenWait(tester, _photoPaidCta)};
  },
};

/// 로그인 → 나 탭 → 15b → "10 쓰고 만들기" 를 누르고 바로 멈춤 말 — 여기서 죽는다.
Future<Map<String, Object?>?> _klPress(WidgetTester tester, Map<String, dynamic> job) =>
    _session((tester, job) async {
      await _openMe(tester);
      await _photoOpenSheet(tester);
      await _photoPress(tester, find.descendant(of: find.byType(SafetySheet), matching: find.text(_photoPaidCta)));
      await say({'step': 'pressed'}); // 답을 기다리지 않는다
      await wait(tester, const Duration(seconds: 30)); // 여기서 죽는다 — 안 죽으면 PC 는 이미 끝냈다
      return null;
    })(tester, job);
