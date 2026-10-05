part of 'area5.dart';

// 영역 5 폰 A 한 대 · 화면 읽기 16개(묶음 area5-read). PC 쪽은 e2e/area5_read.py 의 같은 번호 — 계정 · DB 를 준비하고 판정한다.
// 앱은 화면을 열어 본 것을 Map 으로 말한다(문구는 사람이 읽는 글자 그대로, 못 본 것은 null). 시스템 뒤로는 PC 가 보낸다 —
// 앱은 `step` 에서 멈춰 PC 가 adb 로 KEYCODE_BACK 을 보내고 go 를 넣기를 기다린다.
// 누르기는 줄 전체 폭 위젯의 가운데가 아니라 안의 글자 · 아이콘 · 버튼을 누른다(MessageBubble 의 Align 이 빈 자리를 누르게 했던 일, #282).

// ── 나 탭 히어로 · 15b 시트 ──────────────────────────────────────────────────────────────────────────

/// 히어로 그림의 파일 이름(주소 맨 끝) — 주소 전체에는 계정 번호가 들어 있어 이름만 말한다. 그림이 없으면 null.
String? _avatarFile(WidgetTester tester) {
  final pictures = find.descendant(
    of: find.byType(ProfileHero),
    matching: find.byWidgetPredicate(
      (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).image?.image is NetworkImage,
    ),
  );
  if (!_has(pictures)) return null;
  final image = (tester.widget<DecoratedBox>(pictures.first).decoration as BoxDecoration).image!.image as NetworkImage;
  return Uri.parse(image.url).pathSegments.last;
}

String? _textOf(WidgetTester tester, Finder finder) => _has(finder) ? tester.widget<Text>(finder.first).data : null;

/// 히어로 알약("다시 만들기 · 10")을 눌러 15b 시트를 열고 보유 하트 줄을 읽은 뒤 "취소" 로 닫는다.
/// 만들기 · 충전 버튼은 누르지 않는다 — "10 쓰고 만들기" 는 유료 AI 를 부른다. 무료 시트(아바타 1장)에는 그 줄이 없어 null.
Future<Map<String, Object?>> _readHeartSheet(WidgetTester tester) async {
  await tap(tester, find.text(_regenPill));
  await pumpUntil(tester, find.byType(SafetySheet));
  final text = _textOf(tester, find.textContaining(_heartLine));
  await tap(tester, find.widgetWithText(SafetySheetButton, _cancel));
  await wait(tester, const Duration(seconds: 1)); // 시트가 닫히는 움직임
  return {'heart_text': text, 'sheet_closed': !_has(find.byType(SafetySheet))};
}

// ── 15-5 읽기 ───────────────────────────────────────────────────────────────────────────────────────

/// 섹션 제목을 화면 위치(스크롤을 감안한 y)로 줄 세운다 — 목록은 보이는 줄만 만들어 제목마다 맨 위에서 내려가며 읽는다.
Future<List<String>> _sectionOrder(WidgetTester tester) async {
  final ys = <String, double>{};
  for (final title in _sectionTitles) {
    await _reveal(tester, find.text(title));
    ys[title] = tester.getTopLeft(find.text(title).first).dy + tester.state<ScrollableState>(_manageScrollable).position.pixels;
  }
  return [..._sectionTitles]..sort((a, b) => ys[a]!.compareTo(ys[b]!));
}

/// 기본 정보 행(`_FactRow` — 라벨 · 값 두 글자)의 값. 행이 없으면 null.
String? _factValue(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  if (!_has(row)) return null;
  final texts = tester.widgetList<Text>(find.descendant(of: row.first, matching: find.byType(Text))).toList();
  return texts.length > 1 ? texts[1].data : null;
}

/// 선호 조건 입구 줄의 보조 글자(`ProfileEntryRow.note`).
String? _entryNote(WidgetTester tester, String title) {
  final rows = find.byWidgetPredicate((w) => w is ProfileEntryRow && w.title == title);
  return _has(rows) ? tester.widget<ProfileEntryRow>(rows.first).note : null;
}

/// 15-5 → 기본 정보 "수정 ›" → 15-6 에서 닉네임 · 키 칸이 켜져 있는지와 풀리는 날 문구를 읽는다(E-ME-28 · 29 · 30).
Future<Map<String, Object?>> _readBasicInfo(WidgetTester tester) async {
  await _openManage(tester);
  await _reveal(tester, find.text(_editLink));
  await tap(tester, find.text(_editLink));
  await pumpUntil(tester, find.byType(BasicInfoEditScreen));
  await wait(tester, const Duration(milliseconds: 500));
  final fields = find.byType(TextField);
  final unlock = find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+월 \d+일부터 바꿀 수 있어요$').hasMatch(w.data ?? ''));
  return {
    'nickname_enabled': tester.widget<TextField>(fields.at(0)).enabled,
    'height_enabled': tester.widget<TextField>(fields.at(1)).enabled,
    'unlock_text': _textOf(tester, unlock),
    'plain_note': _has(find.text('30일에 한 번 바꿀 수 있어요')),
  };
}

// ── 시스템 뒤로 ─────────────────────────────────────────────────────────────────────────────────────

/// 지금 화면(앱바 글자)을 말하고 `step` 에서 멈춘다 — PC 가 시스템 뒤로를 보내고 go 를 넣으면 도착 화면을 말한다.
Future<Map<String, Object?>> _backFrom(WidgetTester tester, String name, {bool? edited}) async {
  final opened = _title(tester);
  await step(name);
  await wait(tester, const Duration(milliseconds: 1500)); // 닫히는 움직임
  return {'step': name, 'opened': opened, 'edited': edited, 'title': _title(tester), 'asked': _asking()};
}

/// 시트가 떠 있는 채 `step` 에서 멈춘다 — 뒤로 뒤에 [sheet] 가 닫혔는지, 어느 화면인지, [other] 시트가 대신 열리지 않았는지 말한다.
Future<Map<String, Object?>> _sheetBack(WidgetTester tester, String name, Finder sheet, {Map<String, Finder> other = const {}}) async {
  final before = _has(sheet);
  await step(name);
  await wait(tester, const Duration(milliseconds: 1500));
  return {
    'step': name,
    'open_before': before,
    'open_after': _has(sheet),
    'title': _title(tester),
    for (final entry in other.entries) entry.key: _has(entry.value),
  };
}

/// 시트가 뒤로에도 안 닫혔으면 "취소" 로 닫는다 — 다음 시트를 보러 가려면 화면이 비어 있어야 한다(안 닫힌 사실은 이미 말했다).
Future<void> _closeIfOpen(WidgetTester tester, Finder sheet) async {
  if (!_has(sheet)) return;
  await tap(tester, find.text(_cancel));
  await wait(tester, const Duration(seconds: 1));
}

final Map<String, Area1Case> area5CasesRead = {
  // ── 나 탭 ──
  'E-ME-01': _session((tester, job) async {
    await _openMe(tester);
    await wait(tester, const Duration(seconds: 1)); // 그림 · 학교 로고가 자리를 잡게
    final hero = find.byType(ProfileHero);
    final name = find.descendant(
      of: hero,
      matching: find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == AppTypography.headline.fontSize),
    );
    return {
      'name_line': _textOf(tester, name),
      'school': _textOf(tester, find.descendant(of: find.byType(SchoolLabel), matching: find.byType(Text))),
      'avatar_file': _avatarFile(tester),
      'badge': _has(find.descendant(of: hero, matching: find.text('학생 인증'))),
      'chip': _has(find.descendant(of: hero, matching: find.text('상대에게 이렇게 보여요'))),
      ...await _readHeartSheet(tester),
    };
  }),
  'E-ME-02': _session((tester, job) async {
    await arrive(tester, 'home');
    await tap(tester, _tab('나'));
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 30) && !_has(find.byType(ProfileHero)) && !_has(find.byType(MeLoadError))) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final hero = _has(find.byType(ProfileHero));
    final error = _has(find.byType(MeLoadError));
    return {'hero': hero, 'load_error': error, if (hero) ...await _readHeartSheet(tester)};
  }),
  'E-ME-03': _session((tester, job) async {
    await _openMe(tester);
    final titles = <String, String?>{};
    await tap(tester, find.byIcon(AppIcons.settings));
    await wait(tester, const Duration(milliseconds: 1500));
    titles['gear'] = _title(tester);
    await _returnTo(tester, '내 프로필');
    await tap(tester, _entry(_previewEntry));
    await wait(tester, const Duration(milliseconds: 1500));
    titles['preview'] = _title(tester);
    await _returnTo(tester, '내 프로필');
    await tap(tester, _entry(_manageEntry));
    await wait(tester, const Duration(milliseconds: 1500));
    titles['manage'] = _title(tester);
    return {'titles': titles};
  }),
  'E-ME-06': _session((tester, job) async {
    await _openMe(tester);
    await tap(tester, _entry(_previewEntry));
    await pumpUntil(tester, find.byType(ProfileCard));
    await wait(tester, const Duration(seconds: 1)); // 카드 안쪽이 다 그려지게
    return {
      'card': true, // pumpUntil 이 카드를 기다려 봤다(못 보면 거기서 실패한다)
      'photos': _has(find.byType(PhotoSlider)),
      'kakao': _has(find.text('카카오톡 아이디')),
      'trust': _has(find.text('신뢰 확인 완료')),
      'report': _has(find.text('신고하기')),
      'block': _has(find.text('차단하기')),
    };
  }),
  'E-ME-08': _session((tester, job) async {
    await _openManage(tester);
    // 맨 위에서 먼저 — 스크롤하면 사진 칸이 화면 밖으로 가 만들어지지 않는다.
    final photos = _has(find.byType(PhotoSlider)) ? tester.widget<PhotoSlider>(find.byType(PhotoSlider)).photos.length : 0;
    final badge = _has(find.text('수락 후 공개'));
    final note = _has(find.text('서로 수락하면 전달돼요'));
    final sections = await _sectionOrder(tester);
    await _reveal(tester, find.text('내 키'));
    return {
      'sections': sections,
      'photos': photos,
      'badge': badge,
      'photo_note': note,
      'facts': {for (final label in ['내 키', 'MBTI', '학과']) label: _factValue(tester, label)},
    };
  }),
  'E-ME-09': _session((tester, job) async {
    await _openManage(tester);
    await _reveal(tester, find.text(_agePref));
    await tester.scrollUntilVisible(find.text(_heightPref), 300, scrollable: _manageScrollable);
    return {'age_note': _entryNote(tester, _agePref), 'height_note': _entryNote(tester, _heightPref)};
  }),
  'E-ME-28': _session((tester, job) => _readBasicInfo(tester)),
  'E-ME-29': _session((tester, job) => _readBasicInfo(tester)),
  'E-ME-30': _session((tester, job) => _readBasicInfo(tester)),

  // ── 탈퇴 ──
  'E-WD-01': _session((tester, job) async {
    await _openMe(tester);
    await _openSettings(tester);
    await _openWithdrawSheet(tester);
    final anchor = find.text(_deletedItems.first);
    final items = _has(anchor)
        ? [
            for (final text in tester.widgetList<Text>(
              find.descendant(of: find.ancestor(of: anchor, matching: find.byType(Column)).first, matching: find.byType(Text)),
            ))
              text.data ?? '',
          ]
        : <String>[];
    return {
      'title': _has(find.text(_firstTitle)),
      'lead': _has(find.text(_deleteLead)),
      'items': items,
      'warning': _has(find.text(_deleteWarning)),
      'buttons': _buttonLabels(tester, find.byType(WithdrawFirstSheet)),
    };
  }),
  'E-WD-03': _session((tester, job) async {
    await _openMe(tester);
    await _openSettings(tester);
    await _openWithdrawSheet(tester);
    await _openFinalSheet(tester);
    final finalButtons = _buttonLabels(tester, find.byType(WithdrawFinalSheet)); // 읽기만 — 이 시트의 탈퇴 버튼은 누르지 않는다
    await tap(tester, find.text(_cancel));
    await wait(tester, const Duration(seconds: 1));
    return {'final_seen': true, 'final_buttons': finalButtons, 'closed': !_has(find.text(_finalTitle)), 'title': _title(tester)};
  }),
  'E-WD-17': _session((tester, job) async {
    await arrive(tester, 'suspended');
    final link = find.widgetWithText(TextButton, _withdraw);
    final buttons = [for (final b in tester.widgetList<AppButton>(find.byType(AppButton))) b.label];
    final hasLink = _has(link);
    var sheet = false;
    if (hasLink) {
      await tap(tester, link);
      sheet = await appears(tester, find.text(_suspendedSheetTitle), const Duration(seconds: 5)) != null;
    }
    return {'buttons': buttons, 'withdraw_link': hasLink, 'sheet': sheet, 'warning': _has(find.text(_suspendedWarning))};
  }),

  // ── 시스템 뒤로 · 경계 ──
  'E-EDGE-13': _session((tester, job) async {
    final walks = <Map<String, Object?>>[];
    // 15-5 → 15 (고칠 값이 없다 — 열기만)
    await _openManage(tester);
    walks.add(await _backFrom(tester, '15-5'));
    await _returnTo(tester, '내 프로필');
    // 15-4 → 15
    await tap(tester, _entry(_previewEntry));
    await pumpUntil(tester, find.byType(ProfileCard));
    walks.add(await _backFrom(tester, '15-4'));
    await _returnTo(tester, '내 프로필');
    // 15c(자기소개를 고친 채) → 15-5
    await tap(tester, _entry(_manageEntry));
    await pumpUntil(tester, find.text(_sectionTitles.first));
    await _reveal(tester, _entry(_bioEntry));
    await tap(tester, _entry(_bioEntry));
    await pumpUntil(tester, find.byType(ProfileEditScreen));
    await wait(tester, const Duration(milliseconds: 500));
    const bio = '고치다 만 글';
    await type(tester, find.byType(TextField).first, bio);
    walks.add(await _backFrom(tester, '15c', edited: fieldText(tester, find.byType(TextField)) == bio));
    await _returnTo(tester, '프로필 편집');
    // 06-1(나이 "상관없어요" 를 바꾼 채) → 15-5
    await _reveal(tester, _entry(_agePref));
    await tap(tester, _entry(_agePref));
    await pumpUntil(tester, find.byType(IdealConditionsScreen));
    await wait(tester, const Duration(milliseconds: 500));
    final ignored = tester.widget<Checkbox>(find.byType(Checkbox).first).value;
    await tap(tester, find.text(_ageIgnore));
    walks.add(await _backFrom(tester, '06-1', edited: tester.widget<Checkbox>(find.byType(Checkbox).first).value != ignored));
    await _returnTo(tester, '프로필 편집');
    // 태그 편집(칩 하나를 더 고른 채) → 15c
    await _reveal(tester, _entry(_bioEntry));
    await tap(tester, _entry(_bioEntry));
    await pumpUntil(tester, find.byType(ProfileEditScreen));
    await tap(tester, find.text('수정').first); // 관심사 섹션
    await pumpUntil(tester, find.byType(TagPickerScreen));
    await wait(tester, const Duration(milliseconds: 500));
    final chips = tester.widgetList<SelectChip>(find.byType(SelectChip)).toList();
    final picked = chips.where((chip) => chip.isSelected).length;
    await tap(tester, find.byType(SelectChip).at(chips.indexWhere((chip) => !chip.isSelected)));
    final picked2 = tester.widgetList<SelectChip>(find.byType(SelectChip)).where((chip) => chip.isSelected).length;
    walks.add(await _backFrom(tester, 'tag', edited: picked2 == picked + 1));
    await _returnTo(tester, '프로필 편집');
    // 15-6(키를 고친 채) → 15-5
    await _reveal(tester, find.text(_editLink));
    await tap(tester, find.text(_editLink));
    await pumpUntil(tester, find.byType(BasicInfoEditScreen));
    await wait(tester, const Duration(milliseconds: 500));
    final height = find.byType(TextField).at(1);
    final next = '${(int.tryParse(fieldText(tester, height)) ?? 170) + 1}';
    await type(tester, height, next);
    walks.add(await _backFrom(tester, '15-6', edited: fieldText(tester, height) == next));
    await _returnTo(tester, '프로필 편집');
    // 15-7(사진 한 장을 뺀 채) → 15-5
    await _reveal(tester, find.text(_replacePhotos));
    await tap(tester, find.text(_replacePhotos));
    await pumpUntil(tester, find.byType(MyPhotosScreen));
    await wait(tester, const Duration(milliseconds: 500));
    final removable = find.byIcon(AppIcons.x).evaluate().length;
    await tap(tester, find.byIcon(AppIcons.x).first);
    await wait(tester, const Duration(milliseconds: 500));
    walks.add(await _backFrom(tester, '15-7', edited: find.byIcon(AppIcons.x).evaluate().length == removable - 1));
    return {'walks': walks};
  }),
  'E-EDGE-14': _session((tester, job) async {
    final sheets = <Map<String, Object?>>[];
    // 15b — 나 탭 히어로 알약
    await _openMe(tester);
    await tap(tester, find.text(_regenPill));
    await pumpUntil(tester, find.byType(SafetySheet));
    sheets.add(await _sheetBack(tester, 'regen', find.byType(SafetySheet)));
    await _closeIfOpen(tester, find.byType(SafetySheet));
    // 16c 1차 — 설정 "탈퇴하기"
    await _openSettings(tester);
    await _openWithdrawSheet(tester);
    sheets.add(await _sheetBack(tester, 'withdraw-first', find.text(_firstTitle), other: {'final_open': find.text(_finalTitle)}));
    await _closeIfOpen(tester, find.text(_finalTitle));
    await _closeIfOpen(tester, find.text(_firstTitle));
    // 16c 최종 — 1차 시트의 "영구 삭제" 로 연 시트(탈퇴 버튼은 누르지 않는다)
    await _openWithdrawSheet(tester);
    await _openFinalSheet(tester);
    sheets.add(await _sheetBack(tester, 'withdraw-final', find.text(_finalTitle), other: {'first_open': find.text(_firstTitle)}));
    return {'sheets': sheets};
  }),
  'E-EDGE-16': _session((tester, job) async {
    await arrive(tester, 'consent');
    await step('back'); // PC 가 시스템 뒤로를 보내고 맨 앞 화면을 본다
    await wait(tester, const Duration(seconds: 2));
    return {'on_consent': _has(screen('consent'))};
  }),
  'E-EDGE-23': _session((tester, job) async {
    await _openMe(tester);
    final row = _entry(_manageEntry);
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row); // 첫 번째 누름
    await tester.pump(const Duration(milliseconds: 100));
    // 두 번째 누름 — 새 화면이 덮은 자리에 떨어질 수 있다(실제 손가락과 같다). 그 화면이 이미 가려졌으면 누를 줄이 없다.
    final second = _has(row);
    if (second) await tester.tap(row, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await wait(tester, const Duration(seconds: 2));
    final before = _title(tester);
    final stacked = find.byType(ProfileManageScreen, skipOffstage: false).evaluate().length;
    await _back(tester); // 뒤로 한 번(앱바 화살표)
    return {
      'before': before,
      'second_tap': second,
      'stacked': stacked,
      'on_profile': _has(find.byType(ProfileHero)),
      'manage_again': _has(find.byType(ProfileManageScreen)),
      'title': _title(tester),
    };
  }),
};
