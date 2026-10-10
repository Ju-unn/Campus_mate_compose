part of 'area5.dart';

// 영역 5 폰 A 한 대 · 글 · 태그 · 조건 · 기본 정보를 고쳐 저장하는 16개(묶음 area5-act). PC 쪽은 e2e/area5_act.py 의 같은 번호 —
// 계정 · DB 를 준비하고 판정한다. 앱은 화면을 열어 고치고(저장하는 가설은 저장하고) 본 것을 Map 으로 말한다(문구는 사람이 읽는 글자 그대로, 못 본 것은 null).
// 누르기는 줄 전체 폭 위젯의 가운데가 아니라 안의 글자 · 아이콘 · 버튼을 누른다(#282). 이 파일의 이름은 모두 `_act` 로 시작한다 — 같은 라이브러리의
// 다른 area5 파일(사진 · 아바타)과 이름이 겹치지 않게.
// 이 파일에 탈퇴 · 삭제 버튼을 누르는 줄은 없다.

const _actSave = '저장';
const _actManageTitle = '프로필 편집'; // profile_manage_screen.dart 앱바
const _actBioTitle = '자기소개·태그 수정'; // profile_edit_screen.dart 앱바
const _actIdealTitle = '이상형 조건 수정'; // ideal_conditions_screen.dart 편집 모드 앱바
const _actBasicTitle = '기본 정보 수정'; // basic_info_edit_screen.dart 앱바
const _actSavedToast = '저장했어요'; // me_toast.dart savedToast
const _actNicknameOk = '사용할 수 있는 닉네임이에요';
const _actNicknameBad = '한글 또는 영문 2~5자로 입력해 주세요';
const _actNicknameTaken = '이미 있는 닉네임이에요';
const _actNicknameChecking = '확인 중…'; // basic_info_edit_view_model.dart nicknameChecking
const _actNicknameSoon = '닉네임은 30일에 한 번 바꿀 수 있어요'; // 서버 409 문구(core/errors.py NICKNAME_CHANGE_TOO_SOON)
const _actHeightBad = '숫자 3자리를 확인해 주세요';
const _actHeightIgnore = '키는 상관없어요'; // ideal_conditions_screen.dart 체크 줄(나이는 area5.dart `_ageIgnore`)
const _actEdit = '수정'; // 15c 태그 섹션 "수정 ›" 의 글자
// 06-1 얼굴상 · 인상 라벨(profile_enums.dart)
const _actDog = '강아지상';
const _actCat = '고양이상';
const _actFox = '여우상';
const _actBear = '곰상';
const _actRabbit = '토끼상';
const _actArab = '아랍상';
const _actTofu = '두부상';
const _actKind = '선한상';
const _actChic = '시크상';
const _actInnocent = '청순상';

final _actAgeSummary = RegExp(r'^\d+세 ~ \d+세( 이상)?$'); // ideal_conditions_screen.dart _ageSummary
final _actHeightSummary = RegExp(r'^\d+cm( 이하)? ~ \d+cm( 이상)?$'); // _heightSummary

Finder get _actNicknameField => find.byType(TextField).at(0);
Finder get _actHeightField => find.byType(TextField).at(1);

bool _actSaveEnabled(WidgetTester tester) => enabled(tester, _actSave);

// ── 이동 ────────────────────────────────────────────────────────────────────────────────────────────

/// 15-5 → "자기소개 · 태그" 입구 → 15c.
Future<void> _actEnterBio(WidgetTester tester) async {
  await _reveal(tester, _entry(_bioEntry));
  await tap(tester, _entry(_bioEntry));
  await pumpUntil(tester, find.byType(ProfileEditScreen));
  await wait(tester, const Duration(milliseconds: 500));
}

/// 15-5 → 기본 정보 "수정 ›" → 15-6.
Future<void> _actEnterBasic(WidgetTester tester) async {
  await _reveal(tester, find.text(_editLink));
  await tap(tester, find.text(_editLink));
  await pumpUntil(tester, find.byType(BasicInfoEditScreen));
  await _actUntil(tester, () => _title(tester) == _actBasicTitle);
  await wait(tester, const Duration(milliseconds: 500));
}

/// 15-5 → "이상형 조건 수정" 입구 → 06-1(편집 모드).
Future<void> _actEnterIdeal(WidgetTester tester) async {
  await _reveal(tester, _entry(_idealEntry));
  await tap(tester, _entry(_idealEntry));
  await pumpUntil(tester, find.byType(IdealConditionsScreen));
  await _actUntil(tester, () => _title(tester) == _actIdealTitle);
  await wait(tester, const Duration(milliseconds: 500));
}

// ── 기다리기 · 읽기 ─────────────────────────────────────────────────────────────────────────────────

/// [done] 이 참이 될 때까지 프레임을 흘린다 — 시간이 다 되면 지금 값을 돌려준다(못 닿은 사실은 호출한 쪽이 말한다).
Future<bool> _actUntil(WidgetTester tester, bool Function() done, {Duration timeout = const Duration(seconds: 15)}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout && !done()) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return done();
}

/// 앱바 글자가 [title] 이 될 때까지(저장하고 닫히는 화면을 기다린다). 닫히는 움직임까지 쉬고 지금 앱바 글자를 돌려준다.
Future<String?> _actUntilTitle(WidgetTester tester, String title, {Duration timeout = const Duration(seconds: 30)}) async {
  await _actUntil(tester, () => _title(tester) == title, timeout: timeout);
  await wait(tester, const Duration(milliseconds: 600));
  return _title(tester);
}

/// 저장 뒤 15-5 가 내 프로필을 새로 읽어 첫 섹션이 그려질 때까지.
Future<void> _actManageLoaded(WidgetTester tester) => _actUntil(tester, () => _has(find.text(_sectionTitles.first)));

/// [within] 아래 글자 중 [tag] 가 든 것의 전체 글자.
List<String> _actTextsWith(WidgetTester tester, Finder within, String tag) => [
      for (final text in tester.widgetList<Text>(find.descendant(of: within, matching: find.byType(Text))))
        if ((text.data ?? '').contains(tag)) text.data!,
    ];

/// 화면에서 [pattern] 에 맞는 첫 글자.
String? _actSummary(WidgetTester tester, RegExp pattern) =>
    _textOf(tester, find.byWidgetPredicate((w) => w is Text && pattern.hasMatch(w.data ?? '')));

/// 토스트 "저장했어요" 가 나타난 때부터 사라진 때까지(ms). 안 나타나면 seen=false.
Future<Map<String, Object?>> _actToast(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  Duration? seen;
  int? shownMs;
  while (watch.elapsed < const Duration(seconds: 25)) {
    await tester.pump(const Duration(milliseconds: 50));
    final up = _has(find.text(_actSavedToast));
    if (up && seen == null) seen = watch.elapsed;
    if (!up && seen != null) {
      shownMs = (watch.elapsed - seen).inMilliseconds;
      break;
    }
  }
  return {'toast_seen': seen != null, 'toast_ms': shownMs};
}

/// 15-6 의 "저장" 을 눌러 15-5 로 돌아와 토스트가 뜨고 지나갈 때까지 — 눌렀을 때 버튼이 켜져 있었는지와 토스트 · 도착 화면을 말한다.
Future<Map<String, Object?>> _actSaveBasic(WidgetTester tester) async {
  final pressedEnabled = _actSaveEnabled(tester);
  await tap(tester, button(_actSave));
  final toast = await _actToast(tester);
  await _actManageLoaded(tester);
  return {'save_enabled': pressedEnabled, ...toast, 'title': _title(tester)};
}

/// 닉네임 칸에 [text] 를 치고 형식 · 중복 확인 결과가 뜰 때까지(디바운스 0.3초 + 서버) 기다려 본 것을 말한다.
/// 입력칸은 한글 · 영문 말고는 걸러 내므로 칸에 남은 글자를 따로 말한다.
Future<Map<String, Object?>> _actProbeNickname(WidgetTester tester, String text, {Duration within = const Duration(seconds: 6)}) async {
  await type(tester, _actNicknameField, text);
  final verdict = find.byWidgetPredicate(
    (w) => w is Text && (w.data == _actNicknameOk || w.data == _actNicknameBad || w.data == _actNicknameTaken),
  );
  await appears(tester, verdict, within);
  return {
    'typed': text,
    'field': fieldText(tester, _actNicknameField),
    'ok': _has(find.text(_actNicknameOk)),
    'bad': _has(find.text(_actNicknameBad)),
    'taken': _has(find.text(_actNicknameTaken)),
    'save_enabled': _actSaveEnabled(tester),
  };
}

// ── 자기소개 저장(07 · 18) ──────────────────────────────────────────────────────────────────────────

/// 15-5 → 15c 에서 자기소개를 [job]['bio'] 로 바꿔 "저장" → 15-5 로 돌아와 새 글이 보일 때까지. 저장은 서버가 임베딩(유료)을 부른다.
Future<Map<String, Object?>> _actSaveBio(WidgetTester tester, Map<String, dynamic> job) async {
  final tag = job['tag'] as String;
  await _openManage(tester);
  await _actEnterBio(tester);
  await type(tester, find.byType(TextField).first, job['bio'] as String);
  await tap(tester, button(_actSave));
  final title = await _actUntilTitle(tester, _actManageTitle);
  await _actUntil(tester, () => _has(find.textContaining(tag)));
  return {'title': title, 'manage_bios': _actTextsWith(tester, find.byType(ProfileManageScreen), tag)};
}

// ── 키만 고치기(19 · 34) ────────────────────────────────────────────────────────────────────────────

Area1Case _actHeightOnly() => _session((tester, job) async {
      await _openManage(tester);
      await _actEnterBasic(tester);
      final before = fieldText(tester, _actHeightField);
      await type(tester, _actHeightField, job['height'] as String);
      return {'before': before, ...await _actSaveBasic(tester)};
    });

// ── 06-1 읽기 ───────────────────────────────────────────────────────────────────────────────────────

List<String> _actAnimals(WidgetTester tester) =>
    [for (final type in tester.widget<AnimalTypePicker>(find.byType(AnimalTypePicker)).selected) type.name];

List<String> _actImpressions(WidgetTester tester) =>
    [for (final type in tester.widget<ImpressionTypePicker>(find.byType(ImpressionTypePicker)).selected) type.name];

Future<void> _actPickAnimal(WidgetTester tester, String label) =>
    tap(tester, find.descendant(of: find.byType(AnimalTypePicker), matching: find.text(label)));

Future<void> _actPickImpression(WidgetTester tester, String label) =>
    tap(tester, find.descendant(of: find.byType(ImpressionTypePicker), matching: find.text(label)));

/// 06-1 "저장" 을 눌러 15-5 로 돌아와 선호 조건 한 줄(나이 · 키가 한 노트)을 읽는다 — 새로 읽는 동안 낡은 글자를 읽지 않게 [wantNote] 가 될 때까지 기다린다.
Future<Map<String, Object?>> _actSaveIdeal(WidgetTester tester, String wantNote) async {
  await tap(tester, button(_actSave));
  final back = await _actUntilTitle(tester, _actManageTitle);
  await _actManageLoaded(tester);
  await wait(tester, const Duration(milliseconds: 500));
  await _reveal(tester, _entry(_idealEntry));
  await _actUntil(tester, () => _entryNote(tester, _idealEntry) == wantNote);
  return {'back_title': back, 'ideal_note': _entryNote(tester, _idealEntry)};
}

// ── 태그 편집(21) ───────────────────────────────────────────────────────────────────────────────────

Finder _actChip(String label) => find.byWidgetPredicate((w) => w is SelectChip && w.label == label);

List<String> _actSelectedChips(WidgetTester tester) =>
    [for (final chip in tester.widgetList<SelectChip>(find.byType(SelectChip))) if (chip.isSelected) chip.label];

final Map<String, Area1Case> area5CasesAct = {
  // ── 자기소개 ──
  'E-ME-07': _session((tester, job) async {
    final saved = await _actSaveBio(tester, job);
    await _back(tester); // 15-5 → 15
    await pumpUntil(tester, find.byType(ProfileHero));
    await tap(tester, _entry(_previewEntry));
    await pumpUntil(tester, find.byType(ProfileCard));
    await wait(tester, const Duration(seconds: 1)); // 카드 안쪽이 다 그려지게
    final card = find.byType(ProfileCard);
    return {
      'save_title': saved['title'],
      'card_bios': _actTextsWith(tester, card, job['tag'] as String),
      'old_in_card': _has(find.descendant(of: card, matching: find.text(job['old'] as String))),
    };
  }),
  'E-ME-18': _session((tester, job) => _actSaveBio(tester, job)),
  'E-ME-19': _actHeightOnly(),
  'E-ME-20': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBio(tester);
    final field = find.byType(TextField).first;
    await type(tester, field, '');
    final cleared = _actSaveEnabled(tester);
    await type(tester, field, '   ');
    final spaces = _actSaveEnabled(tester);
    await type(tester, field, '다시 쓴 글'); // 꺼진 채로만 있으면 위 둘이 증거가 못 된다
    return {'clear_enabled': cleared, 'spaces_enabled': spaces, 'typed_enabled': _actSaveEnabled(tester)};
  }),

  // ── 태그 ──
  'E-ME-21': _session((tester, job) async {
    final extra = job['extra'] as String;
    await _openManage(tester);
    await _actEnterBio(tester);
    await tap(tester, find.text(_actEdit).first); // 관심사 섹션의 "수정 ›"
    await pumpUntil(tester, find.byType(TagPickerScreen));
    await wait(tester, const Duration(milliseconds: 500));
    final start = _actSelectedChips(tester);
    await tap(tester, _actChip(extra));
    final five = _actSelectedChips(tester);
    await tap(tester, _actChip(job['sixth'] as String)); // 6번째 — 안 골라져야 한다
    final afterSixth = _actSelectedChips(tester);
    final off = five.take(3).toList();
    for (final label in off) {
      await tap(tester, _actChip(label));
    }
    final two = _actSelectedChips(tester);
    final twoSave = _actSaveEnabled(tester);
    for (final label in off) {
      await tap(tester, _actChip(label)); // 같은 3개를 다시 켜 5개로
    }
    final backToFive = _actSelectedChips(tester);
    await tap(tester, button(_actSave));
    final title = await _actUntilTitle(tester, _actBioTitle);
    await _actUntil(tester, () => _has(find.text(extra))); // 15c 가 새 칩을 그릴 때까지
    final chips = [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: find.byKey(const ValueKey('tag-chip')), matching: find.byType(Text)),
      ))
        text.data ?? '',
    ];
    return {
      'start': start,
      'five': five,
      'after_sixth': afterSixth,
      'two': two,
      'two_save_enabled': twoSave,
      'back_to_five': backToFive,
      'title': title,
      'chips': chips,
    };
  }),
  'E-ME-23': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBio(tester);
    final field = find.byType(TextField).first;
    final first = fieldText(tester, field);
    await type(tester, field, job['typed'] as String);
    final typed = fieldText(tester, field);
    await _back(tester); // 저장하지 않고 닫는다
    await _actUntilTitle(tester, _actManageTitle);
    await _actEnterBio(tester);
    return {'first_field': first, 'typed_field': typed, 'reopened_field': fieldText(tester, find.byType(TextField).first)};
  }),

  // ── 선호 조건 ──
  'E-ME-24': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterIdeal(tester);
    final title = _title(tester);
    final firstAge = _actSummary(tester, _actAgeSummary);
    final firstHeight = _actSummary(tester, _actHeightSummary);
    // 손가락으로 끌지 않고 슬라이더의 onChanged 를 부른다(24~30) — 끌기 자체는 사람이 실기기에서 본다.
    tester.widget<RangeSlider>(find.byType(RangeSlider).first).onChanged!(const RangeValues(24, 30));
    await tester.pump(const Duration(milliseconds: 300));
    final changedAge = _actSummary(tester, _actAgeSummary);
    final saved = await _actSaveIdeal(tester, '나이 24–30세 · 키 165–180cm');
    return {
      'title': title,
      'first_age': firstAge,
      'first_height': firstHeight,
      'changed_age': changedAge,
      'back_title': saved['back_title'],
      'ideal_note': saved['ideal_note'],
    };
  }),
  'E-ME-25': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterIdeal(tester);
    await tap(tester, find.text(_ageIgnore));
    await tap(tester, find.text(_actHeightIgnore));
    final boxes = [for (final box in tester.widgetList<Checkbox>(find.byType(Checkbox))) box.value];
    final saved = await _actSaveIdeal(tester, '나이 · 키 모두 상관없어요');
    return {
      'age_ignored': boxes.isNotEmpty && boxes[0] == true,
      'height_ignored': boxes.length > 1 && boxes[1] == true,
      'back_title': saved['back_title'],
      'ideal_note': saved['ideal_note'],
    };
  }),
  'E-ME-26': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterIdeal(tester);
    final animalStart = _actAnimals(tester);
    await _actPickAnimal(tester, _actDog); // 있던 1개를 끈다
    final animalZero = _actAnimals(tester);
    final animalZeroSave = _actSaveEnabled(tester);
    for (final label in [_actCat, _actFox, _actBear]) {
      await _actPickAnimal(tester, label);
    }
    final animalThree = _actAnimals(tester);
    await _actPickAnimal(tester, _actRabbit); // 4번째 — 안 켜져야 한다
    final animalFour = _actAnimals(tester);
    final impressionStart = _actImpressions(tester);
    await _actPickImpression(tester, _actKind);
    final impressionZero = _actImpressions(tester);
    final impressionZeroSave = _actSaveEnabled(tester);
    for (final label in [_actArab, _actTofu, _actChic]) {
      await _actPickImpression(tester, label);
    }
    final impressionThree = _actImpressions(tester);
    final threeSave = _actSaveEnabled(tester);
    await _actPickImpression(tester, _actInnocent);
    final impressionFour = _actImpressions(tester);
    return {
      'animal_start': animalStart,
      'animal_zero': animalZero,
      'animal_zero_save': animalZeroSave,
      'animal_three': animalThree,
      'animal_four': animalFour,
      'impression_start': impressionStart,
      'impression_zero': impressionZero,
      'impression_zero_save': impressionZeroSave,
      'impression_three': impressionThree,
      'impression_four': impressionFour,
      'three_save': threeSave,
    };
  }),

  // ── 닉네임 ──
  'E-ME-27': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    final probe = await _actProbeNickname(tester, job['nickname'] as String);
    final saved = await _actSaveBasic(tester);
    return {
      'ok': probe['ok'],
      'field': probe['field'],
      'save_enabled': saved['save_enabled'],
      'toast_seen': saved['toast_seen'],
      'toast_ms': saved['toast_ms'],
      'title': saved['title'],
    };
  }),
  'E-ME-31': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    final enabledAtOpen = tester.widget<TextField>(_actNicknameField).enabled;
    await step('opened'); // PC 가 nickname_changed_at 을 지금으로 바꾼다(다른 곳에서 바꾼 것처럼)
    final probe = await _actProbeNickname(tester, job['nickname'] as String);
    await tap(tester, button(_actSave));
    final error = find.text(_actNicknameSoon);
    await appears(tester, error, const Duration(seconds: 10));
    final seen = _has(error);
    final line = find.ancestor(of: error, matching: find.byType(Row)).first;
    return {
      'enabled_at_open': enabledAtOpen,
      'ok_before': probe['ok'],
      'error': seen,
      'error_icon': seen && _has(find.descendant(of: line, matching: find.byIcon(AppIcons.circleAlert))),
      'error_color': seen ? tester.widget<Text>(error.first).style?.color?.toARGB32() : null,
      'on_edit': _has(find.byType(BasicInfoEditScreen)),
      'title': _title(tester),
    };
  }),
  'E-ME-33': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    final probes = <Map<String, Object?>>[];
    for (final typed in (job['typed'] as List<dynamic>).cast<String>()) {
      probes.add(await _actProbeNickname(tester, typed));
    }
    return {'probes': probes};
  }),
  'E-ME-34': _actHeightOnly(),

  // ── 키 ──
  'E-ME-35': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    final rows = <Map<String, Object?>>[];
    for (final typed in (job['bad'] as List<dynamic>).cast<String>()) {
      await type(tester, _actHeightField, typed);
      await wait(tester, const Duration(milliseconds: 400));
      rows.add({'typed': typed, 'error': _has(find.text(_actHeightBad)), 'save_enabled': _actSaveEnabled(tester)});
    }
    for (final typed in (job['good'] as List<dynamic>).cast<String>()) {
      await type(tester, _actHeightField, typed);
      await wait(tester, const Duration(milliseconds: 400));
      final error = _has(find.text(_actHeightBad));
      final saved = await _actSaveBasic(tester);
      await _actEnterBasic(tester); // 저장된 값이 서버에서 다시 와서 칸에 채워지는지
      rows.add({
        'typed': typed,
        'error': error,
        'save_enabled': saved['save_enabled'],
        'title': saved['title'],
        'reopened': fieldText(tester, _actHeightField),
      });
    }
    return {'rows': rows};
  }),
  'E-ME-36': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    final untouched = _actSaveEnabled(tester);
    final height = fieldText(tester, _actHeightField);
    final nickname = fieldText(tester, _actNicknameField);
    await type(tester, _actHeightField, '${(int.tryParse(height) ?? 170) + 1}');
    final heightChanged = _actSaveEnabled(tester);
    await type(tester, _actHeightField, height);
    final heightBack = _actSaveEnabled(tester);
    await type(tester, _actNicknameField, job['other'] as String);
    await appears(tester, find.text(_actNicknameOk), const Duration(seconds: 6));
    final nickChanged = _actSaveEnabled(tester);
    await type(tester, _actNicknameField, nickname);
    await wait(tester, const Duration(milliseconds: 800)); // 되돌리면 묻지 않는다 — 지난 판정이 지워질 시간
    final nickBack = _actSaveEnabled(tester);
    return {
      'untouched_enabled': untouched,
      'height_changed_enabled': heightChanged,
      'height_back_enabled': heightBack,
      'nick_changed_enabled': nickChanged,
      'nick_back_enabled': nickBack,
      'height': height,
      'nickname': nickname,
    };
  }),
  'E-EDGE-02': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    await step('cut');
    await type(tester, _actNicknameField, job['nickname'] as String);
    await wait(tester, const Duration(milliseconds: 600));
    // 망이 끊겼으면 확인 요청이 실패해 '확인 중…' 이 사라진다. 10초를 기다려도 남아 있으면 PC 가 "끊긴 증거 없음" 으로 본다(문구 0개 · 버튼 켜짐은 느린 응답에서도 참).
    final checkingWatch = Stopwatch()..start();
    while (_has(find.text(_actNicknameChecking)) && checkingWatch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final offline = {
      'off_ok': _has(find.text(_actNicknameOk)),
      'off_bad': _has(find.text(_actNicknameBad)),
      'off_taken': _has(find.text(_actNicknameTaken)),
      'off_checking': _has(find.text(_actNicknameChecking)),
      'off_field': fieldText(tester, _actNicknameField),
      'off_save_enabled': _actSaveEnabled(tester),
    };
    await step('restore');
    final saved = await _actSaveBasic(tester);
    return {...offline, ...saved};
  }),
};
