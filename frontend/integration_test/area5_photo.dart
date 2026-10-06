part of 'area5.dart';

// 영역 5 폰 A 한 대 · 아바타 다시 만들기 3개(12 · 13 · 14)와 15-7 사진 수정 5개(38 · 39 · 41 · 42 · 44)(묶음 area5-photo). PC 쪽은 e2e/area5_photo.py 의 같은 번호 —
// 계정 · DB 를 준비하고 판정한다. 앱은 화면을 열어 누르고 본 것을 Map 으로 말한다(문구는 사람이 읽는 글자 그대로, 못 본 것은 null).
// 누르기는 줄 전체 폭 위젯의 가운데가 아니라 안의 글자 · 아이콘 · 버튼 안의 글자를 누른다(#282). 이 파일의 이름은 모두 `_photo` 로 시작한다 — 같은 라이브러리의
// 다른 area5 파일(`_act` 등)과 겹치지 않게. 기다리기 도우미(`_actUntil` · `_actUntilTitle`)는 area5_act.dart 의 것을 그대로 쓴다.
// 15-7 의 갤러리 훅은 04-2 의 photosViewModelProvider 가 아니라 15-7 이 쓰는 myPhotosViewModelProvider.notifier.pickFromGallery 다.
// 얼굴 판정은 기기 안 ML Kit 이라 얼굴 있는 · 없는 사진은 PC 가 폰 앱 캐시(e2e-photos/)로 옮겨 둔 사진 세트 파일을 쓴다(area1_b3.dart 와 같다).
// 이 파일에 탈퇴 · 영구 삭제 버튼을 누르는 줄은 없다.

const _photoSave = '저장';
const _photoEditTitle = '사진 수정'; // my_photos_screen.dart 앱바(EditAppBar)
const _photoManageTitle = '프로필 편집'; // profile_manage_screen.dart 앱바
const _photoLowTitle = '하트가 모자라요'; // 15b-3 시트 제목 · 서버 HEARTS_NOT_ENOUGH(402 문구)
const _photoCharge = '하트 충전하기';
const _photoPaidCta = '10 쓰고 만들기';
const _photoSoon = '곧 열려요'; // me_toast.dart comingSoonToast
const _photoGenerating = '아바타로 변환 중이에요'; // my_profile_screen.dart 변환 중 안내
const _photoFailedToast = '아바타를 만들지 못했어요.\n하트는 차감되지 않았어요.'; // my_profile_screen.dart 15-3 안내
const _photoMaxNotice = '사진은 최대 4장까지 올릴 수 있어요'; // photos_view_model.dart addPhoto
const _photoChangedNotice = '사진이 바뀌었어요, 다시 열어 주세요'; // 서버 PHOTOS_CHANGED(409)
const _photoNetworkNotice = '네트워크 연결을 확인해 주세요'; // NetworkFailure
const _photoNotSafe = '부적절한 사진은 올릴 수 없어요'; // 서버 PHOTO_NOT_SAFE(422)

// ── 읽기 ────────────────────────────────────────────────────────────────────────────────────────────

/// 15 (나 탭) 에서 쓰는 공급자 모음 — 15-7 이 위에 올라와 있으면 못 찾는다.
ProviderContainer _photoMeContainer(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(ProfileHero)));

/// 15-7 에서 쓰는 공급자 모음.
ProviderContainer _photoEditorContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MyPhotosScreen)));

/// 15-7 칸의 사진 행 id 를 칸 순서대로(방금 고른 새 사진은 id 가 없어 null).
List<String?> _photoIds(ProviderContainer container) => [for (final photo in container.read(myPhotosViewModelProvider).photos) photo.id];

/// 15-7 에 그려진 사진 칸 수.
int _photoTiles(WidgetTester tester) => find.byType(DraggablePhotoTile).evaluate().length;

/// 15-5 실제 사진 슬라이더의 파일 이름들(주소 맨 끝 — 주소 전체에는 계정 번호 · 서명이 들어 있다).
List<String> _photoManageNames(WidgetTester tester) {
  if (!_has(find.byType(PhotoSlider))) return const [];
  return [
    for (final image in tester.widget<PhotoSlider>(find.byType(PhotoSlider)).photos)
      if (image is NetworkImage) Uri.parse(image.url).pathSegments.last,
  ];
}

/// 15b 시트 안의 글자들(맨 앞이 제목).
List<String> _photoSheetTexts(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.descendant(of: find.byType(SafetySheet), matching: find.byType(Text))))
        if ((text.data ?? '').isNotEmpty) text.data!,
    ];

String? _photoLine(List<String> texts, String needle) {
  for (final text in texts) {
    if (text.contains(needle)) return text;
  }
  return null;
}

/// 다시 만들기 뷰모델 상태(idle · generating · ready · failed · fallback) — 시트가 서버를 불렀는지의 증거다(부르면 idle 을 벗어난다).
String _photoRegenState(WidgetTester tester) => _photoMeContainer(tester).read(avatarGenerationViewModelProvider).status.name;

// ── 누르기 · 기다리기 ────────────────────────────────────────────────────────────────────────────────

/// 눌러 놓고 바로 돌아온다 — `tap` 은 누른 뒤 0.3초를 흘려 토스트 시간을 깎는다.
Future<void> _photoPress(WidgetTester tester, Finder finder) async {
  must(_has(finder), '못 찾음: $finder');
  await tester.ensureVisible(finder.last);
  await tester.pump();
  await tester.tap(finder.last);
}

/// [text] 토스트가 나타난 때부터 사라진 때까지(ms). 안 나타나면 (false, null).
Future<(bool, int?)> _photoToast(WidgetTester tester, String text, {Duration within = const Duration(seconds: 25)}) async {
  final watch = Stopwatch()..start();
  Duration? seen;
  int? shownMs;
  while (watch.elapsed < within) {
    await tester.pump(const Duration(milliseconds: 50));
    final up = _has(find.text(text));
    if (up && seen == null) seen = watch.elapsed;
    if (!up && seen != null) {
      shownMs = (watch.elapsed - seen).inMilliseconds;
      break;
    }
  }
  return (seen != null, shownMs);
}

/// 15 → 히어로 알약 "다시 만들기 · 10" → 15b 시트가 올라올 때까지.
Future<void> _photoOpenSheet(WidgetTester tester) async {
  await tap(tester, find.text(_regenPill));
  await pumpUntil(tester, find.byType(SafetySheet));
  await wait(tester, const Duration(milliseconds: 500)); // 시트가 올라오는 움직임
}

/// 15-5 → "실제 사진 교체" → 15-7.
Future<void> _photoOpenEditor(WidgetTester tester) async {
  await _reveal(tester, find.text(_replacePhotos));
  await tap(tester, find.text(_replacePhotos));
  await pumpUntil(tester, find.byType(MyPhotosScreen));
  await wait(tester, const Duration(milliseconds: 500)); // 칸이 자리를 잡게
}

/// 15-7 의 "저장" — 버튼 가운데가 아니라 안의 글자를 누른다.
Future<void> _photoTapSave(WidgetTester tester) => tap(tester, find.descendant(of: button(_photoSave), matching: find.text(_photoSave)));

/// PC 가 앱 캐시에 넣어 둔 사진 세트 파일.
Future<File> _photoFile(String name) async {
  final file = File('${(await getTemporaryDirectory()).path}/e2e-photos/$name');
  if (!file.existsSync()) throw E2eBlocked('사진 세트 파일 없음: $name');
  return file;
}

/// 15-7 의 갤러리를 [files] 로 갈아끼운다 — 갤러리에 물은 남은 칸은 [asked] 에 담는다.
void _photoGallery(ProviderContainer container, List<File> files, List<int> asked) {
  container.read(myPhotosViewModelProvider.notifier).pickFromGallery = (limit) async {
    asked.add(limit);
    return files;
  };
}

/// 빈 "사진 추가" 칸의 + 아이콘을 눌러 갤러리가 불리고 얼굴 검사가 끝날 때까지.
Future<void> _photoAdd(WidgetTester tester, ProviderContainer container, List<int> asked) async {
  final before = asked.length;
  await tap(tester, find.byIcon(AppIcons.plus).first);
  await _actUntil(tester, () => asked.length > before);
  await _actUntil(tester, () => !container.read(myPhotosViewModelProvider).isCheckingPhotos, timeout: const Duration(seconds: 20));
  await tester.pump(const Duration(milliseconds: 300)); // 칸 · 안내가 그려지게
}

/// 칸 [from] 을 길게 눌러 칸 [to] 위에서 놓는다 → 'drag'(순서가 맞게 바뀜) · 'swap-call'(끌기가 순서를 못 바꿔 swapPhotos 를 직접 부름) ·
/// 'drag-wrong'(끌었더니 엉뚱한 순서가 됨). 끌기는 두 칸을 맞바꾼다.
Future<String> _photoReorder(WidgetTester tester, ProviderContainer container, int from, int to) async {
  final before = _photoIds(container);
  final want = [...before];
  want[from] = before[to];
  want[to] = before[from];
  final tiles = find.byType(DraggablePhotoTile);
  final start = tester.getCenter(tiles.at(from));
  final end = tester.getCenter(tiles.at(to));
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 700)); // 길게 누르기(500ms)를 넘겨 사진을 집는다
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / steps)!);
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 600));
  final after = _photoIds(container);
  if (after.join('|') == want.join('|')) return 'drag';
  if (after.join('|') != before.join('|')) return 'drag-wrong';
  container.read(myPhotosViewModelProvider.notifier).swapPhotos(from, to); // 끌기가 안 먹었다 — 대체
  await tester.pump(const Duration(milliseconds: 300));
  return 'swap-call';
}

/// 저장을 누르고 15-5 로 돌아와 슬라이더가 [before] 와 달라질 때까지 기다린 뒤 (돌아온 화면 앱바, 15-5 사진 파일 이름들).
Future<(String?, List<String>)> _photoSaveAndWait(WidgetTester tester, List<String> before) async {
  await _photoTapSave(tester);
  final title = await _actUntilTitle(tester, _photoManageTitle);
  await _actUntil(tester, () {
    final names = _photoManageNames(tester);
    return names.isNotEmpty && names.join('|') != before.join('|');
  });
  return (title, _photoManageNames(tester));
}

/// 사진을 고른 뒤의 15-7 — 칸 수 · 안내 · 토스트. [files] 가 갤러리에서 고른 것이다.
Future<Map<String, Object?>> _photoPick(WidgetTester tester, ProviderContainer container, List<File> files) async {
  final asked = <int>[];
  _photoGallery(container, files, asked);
  final before = _photoTiles(tester);
  await _photoAdd(tester, container, asked);
  final message = container.read(myPhotosViewModelProvider).errorMessage;
  final toast = message != null && await appears(tester, find.text(message), const Duration(seconds: 3)) != null;
  return {'before': before, 'after': _photoTiles(tester), 'message': message, 'toast': toast};
}

const _photoFreeCta = '무료로 만들기'; // avatar_regen_sheet.dart 비용 0 시트
const _photoWait = Duration(minutes: 11); // 워커가 새 아바타를 만들기까지 — 서버 · 앱 폴링 상한 10분 + 여유

/// 15b 시트의 [cta] 를 눌러 만들기를 시작하고(변환 중 안내), [midway] 를 한 뒤 히어로 그림이 바뀌고 안내가 사라질 때까지(최대 [_photoWait]) 기다린다.
/// 끝나면 시트 앞 모습 · 새 그림 여부 · 뷰모델 상태를 말한다 — 하트 · 원장 · 아바타 행은 PC 가 DB 로 본다. [midway] 가 돌려준 칸은 그대로 더한다.
Future<Map<String, Object?>> _photoRegenWait(WidgetTester tester, String cta, {Future<Map<String, Object?>> Function()? midway}) async {
  final before = _avatarFile(tester);
  await _photoPress(tester, find.descendant(of: find.byType(SafetySheet), matching: find.text(cta)));
  final generating = await appears(tester, find.text(_photoGenerating), const Duration(seconds: 15));
  final extra = midway == null ? const <String, Object?>{} : await midway();
  final watch = Stopwatch()..start();
  while (watch.elapsed < _photoWait && (_avatarFile(tester) == before || _has(find.text(_photoGenerating)))) {
    await tester.pump(const Duration(milliseconds: 500));
    if (_photoRegenState(tester) == 'failed') break; // 실패로 끝났다 — 11분을 더 기다리지 않는다
  }
  final state = _photoMeContainer(tester).read(avatarGenerationViewModelProvider);
  return {
    'generating_seen': generating != null,
    'avatar_changed': _avatarFile(tester) != before,
    'generating_gone': !_has(find.text(_photoGenerating)),
    'regen_state': state.status.name,
    'waited_ms': watch.elapsedMilliseconds,
    ...extra,
  };
}

final Map<String, Area1Case> area5CasesPhoto = {
  // ── 아바타 다시 만들기 ──
  'E-ME-10': _session((tester, job) async {
    await _openMe(tester);
    await _photoOpenSheet(tester);
    final texts = _photoSheetTexts(tester);
    return {'sheet_title': texts.isEmpty ? null : texts.first, 'sheet_texts': texts, ...await _photoRegenWait(tester, _photoFreeCta)};
  }),
  'E-ME-11': _session((tester, job) async {
    await _openMe(tester);
    await _photoOpenSheet(tester);
    final texts = _photoSheetTexts(tester);
    return {
      'sheet_title': texts.isEmpty ? null : texts.first,
      'sheet_body': _photoLine(texts, _heartLine),
      ...await _photoRegenWait(tester, _photoPaidCta),
    };
  }),
  'E-ME-12': _session((tester, job) async {
    await _openMe(tester);
    await _photoOpenSheet(tester);
    final texts = _photoSheetTexts(tester);
    await _photoPress(tester, find.descendant(of: find.byType(SafetySheet), matching: find.text(_photoCharge)));
    final toast = await _photoToast(tester, _photoSoon);
    return {
      'sheet_title': texts.isEmpty ? null : texts.first,
      'sheet_body': _photoLine(texts, _heartLine),
      'sheet_closed': !_has(find.byType(SafetySheet)),
      'toast_seen': toast.$1,
      'toast_ms': toast.$2,
      'regen_state': _photoRegenState(tester),
    };
  }),
  'E-ME-13': _session((tester, job) async {
    await _openMe(tester);
    await step('opened'); // PC 가 하트를 5로 낮춘다 — 화면은 처음 읽은 37 을 들고 있다
    await _photoOpenSheet(tester);
    final texts = _photoSheetTexts(tester);
    await _photoPress(tester, find.descendant(of: find.byType(SafetySheet), matching: find.text(_photoPaidCta)));
    final toast = await _photoToast(tester, _photoLowTitle);
    final state = _photoMeContainer(tester).read(avatarGenerationViewModelProvider);
    return {
      'sheet_title': texts.isEmpty ? null : texts.first,
      'sheet_body': _photoLine(texts, _heartLine),
      'toast_seen': toast.$1,
      'regen_state': state.status.name,
      'regen_error': state.errorMessage,
    };
  }),
  'E-ME-14': _session((tester, job) async {
    await _openMe(tester);
    await _photoOpenSheet(tester);
    final texts = _photoSheetTexts(tester);
    await step('ready'); // PC 가 새 아바타 행을 지켜보기 시작한다 — 생기면 바로 failed 로 바꾼다
    await _photoPress(tester, find.descendant(of: find.byType(SafetySheet), matching: find.text(_photoPaidCta)));
    final failed = await appears(tester, find.text(_photoFailedToast), const Duration(seconds: 90));
    final state = _photoMeContainer(tester).read(avatarGenerationViewModelProvider);
    return {
      'sheet_body': _photoLine(texts, _heartLine),
      'toast_seen': failed != null,
      'pill_enabled': tester.widget<ProfileHero>(find.byType(ProfileHero)).onRegenerate != null,
      'generating_gone': !_has(find.text(_photoGenerating)),
      'regen_state': state.status.name,
      'regen_error': state.errorMessage,
    };
  }),
  'E-ME-16': _session((tester, job) async {
    await _openMe(tester);
    await _photoOpenSheet(tester);
    return _photoRegenWait(tester, _photoFreeCta, midway: () async {
      await tap(tester, _tab('오늘')); // 만드는 중에 나 탭을 떠난다 — 화면 15 가 닫히며 폴링을 끊는다
      await wait(tester, const Duration(seconds: 5));
      await tap(tester, _tab('나')); // 돌아오면 만드는 중이면 폴링을 다시 잇는다
      await pumpUntil(tester, find.byType(ProfileHero));
      return {'generating_after_return': _has(find.text(_photoGenerating))};
    });
  }),

  // ── 15-7 사진 수정 ──
  'E-ME-38': _session((tester, job) async {
    final face = await _photoFile(job['photo'] as String);
    await _openManage(tester);
    final namesBefore = _photoManageNames(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final idsOpen = _photoIds(container);
    await tap(tester, find.byIcon(AppIcons.x).at(1)); // 두 번째 칸 빼기
    await wait(tester, const Duration(milliseconds: 300));
    final idsRemoved = _photoIds(container);
    final asked = <int>[];
    _photoGallery(container, [face], asked);
    final tilesBefore = _photoTiles(tester);
    await _photoAdd(tester, container, asked);
    if (_photoTiles(tester) < tilesBefore + 1) {
      throw E2eBlocked('얼굴 사진이 기기 얼굴 검사에서 빠짐(칸 $tilesBefore → ${_photoTiles(tester)}) — 사진 세트 확인');
    }
    final idsAdded = _photoIds(container);
    final message = container.read(myPhotosViewModelProvider).errorMessage;
    final saveEnabled = enabled(tester, _photoSave);
    final saved = await _photoSaveAndWait(tester, namesBefore);
    return {
      'names_before': namesBefore,
      'ids_open': idsOpen,
      'ids_removed': idsRemoved,
      'asked': asked,
      'ids_added': idsAdded,
      'message': message,
      'save_enabled': saveEnabled,
      'title': saved.$1,
      'names_after': saved.$2,
    };
  }),
  'E-ME-39': _session((tester, job) async {
    final drag = (job['drag'] as List<dynamic>).cast<int>();
    await _openManage(tester);
    final namesBefore = _photoManageNames(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final idsOpen = _photoIds(container);
    final via = await _photoReorder(tester, container, drag[0], drag[1]);
    final idsDragged = _photoIds(container);
    final saveEnabled = enabled(tester, _photoSave);
    final saved = await _photoSaveAndWait(tester, namesBefore);
    return {
      'names_before': namesBefore,
      'ids_open': idsOpen,
      'via': via,
      'ids_dragged': idsDragged,
      'save_enabled': saveEnabled,
      'title': saved.$1,
      'names_after': saved.$2,
    };
  }),
  'E-ME-40': _session((tester, job) async {
    await _openMe(tester);
    final avatarBefore = _avatarFile(tester);
    await tap(tester, _entry(_manageEntry));
    await pumpUntil(tester, find.text(_sectionTitles.first));
    await wait(tester, const Duration(milliseconds: 500)); // 사진 · 줄이 자리를 잡게
    final namesBefore = _photoManageNames(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final idsOpen = _photoIds(container);
    await tap(tester, find.byIcon(AppIcons.x).first); // 첫 칸(아바타 원본) 빼기
    await wait(tester, const Duration(milliseconds: 300));
    final idsRemoved = _photoIds(container);
    final saved = await _photoSaveAndWait(tester, namesBefore);
    await _back(tester); // 15-5 → 15
    await pumpUntil(tester, find.byType(ProfileHero));
    await wait(tester, const Duration(seconds: 1)); // 내 프로필을 다시 읽어 그림이 자리를 잡게
    final avatarAfter = _avatarFile(tester);
    await _photoOpenSheet(tester);
    return {
      'ids_open': idsOpen,
      'ids_removed': idsRemoved,
      'title': saved.$1,
      'avatar_before': avatarBefore,
      'avatar_after': avatarAfter,
      ...await _photoRegenWait(tester, _photoFreeCta),
    };
  }),
  'E-ME-41': _session((tester, job) async {
    await _openManage(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final asked = <int>[];
    _photoGallery(container, const [], asked);
    Map<String, Object?> count() => {'count': _photoTiles(tester), 'save_enabled': enabled(tester, _photoSave)};
    final steps = <Map<String, Object?>>[count()];
    final plusAtFour = find.byIcon(AppIcons.plus).evaluate().length;
    // 4장이면 빈 칸이 없어 화면으로 누를 곳이 없다 — 그 칸이 부르는 addPhoto 를 직접 부른다.
    await container.read(myPhotosViewModelProvider.notifier).addPhoto();
    final maxToast = await appears(tester, find.text(_photoMaxNotice), const Duration(seconds: 3)) != null;
    final tilesAfterMax = _photoTiles(tester);
    for (var i = 0; i < 3; i++) {
      await tap(tester, find.byIcon(AppIcons.x).first);
      await wait(tester, const Duration(milliseconds: 300));
      steps.add(count());
    }
    return {
      'steps': steps,
      'plus_at_four': plusAtFour,
      'max_toast': maxToast,
      'tiles_after_max': tilesAfterMax,
      'gallery_asked': asked.length,
    };
  }),
  'E-ME-42': _session((tester, job) async {
    final alone = await _photoFile(job['alone'] as String);
    final mixed = [for (final name in (job['mixed'] as List<dynamic>).cast<String>()) await _photoFile(name)];
    await _openManage(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final first = await _photoPick(tester, container, [alone]);
    await wait(tester, const Duration(milliseconds: 2500)); // 먼저 뜬 안내가 사라지게
    final second = await _photoPick(tester, container, mixed);
    if ((second['after'] as int) < (second['before'] as int) + 1) {
      throw E2eBlocked('얼굴 사진이 기기 얼굴 검사에서 빠짐(칸 ${second['before']} → ${second['after']}) — 사진 세트 확인');
    }
    return {'alone': first, 'mixed': second};
  }),
  'E-ME-43': _session((tester, job) async {
    final face = await _photoFile(job['photo'] as String);
    final unsafe = await _photoFile(job['unsafe'] as String);
    await _openManage(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final asked = <int>[];
    _photoGallery(container, [face, unsafe], asked);
    final tilesBefore = _photoTiles(tester);
    await _photoAdd(tester, container, asked);
    final tilesAfter = _photoTiles(tester);
    if (tilesAfter < tilesBefore + 2) {
      throw E2eBlocked('두 사진이 기기 얼굴 검사에서 빠짐(칸 $tilesBefore → $tilesAfter) — 사진 세트의 unsafe.jpg 에 얼굴이 있어야 서버까지 간다');
    }
    await _photoTapSave(tester);
    final error = find.text(_photoNotSafe);
    await appears(tester, error, const Duration(seconds: 30));
    final shown = _has(error);
    return {
      'tiles_before': tilesBefore,
      'tiles_after': tilesAfter,
      'error': shown,
      'error_text': shown ? tester.widget<Text>(error.first).data : null,
      'title_after_error': _title(tester),
    };
  }),
  'E-ME-44': _session((tester, job) async {
    final swap = (job['swap'] as List<dynamic>).cast<int>();
    final left = job['left'] as int;
    await _openManage(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final idsOpen = _photoIds(container);
    await step('opened'); // PC 가 사진 행 하나를 지운다(다른 기기에서 지운 것처럼)
    final via = await _photoReorder(tester, container, swap[0], swap[1]); // 지운 사진 칸은 그대로 두고 다른 칸 순서만 바꾼다
    final idsSwapped = _photoIds(container);
    await _photoTapSave(tester);
    final error = find.text(_photoChangedNotice);
    await appears(tester, error, const Duration(seconds: 30));
    final shown = _has(error);
    final errorText = shown ? tester.widget<Text>(error.first).data : null;
    final titleAfterError = _title(tester);
    int? reopenedTiles;
    List<String?>? reopenedIds;
    if (titleAfterError == _photoEditTitle) {
      await _back(tester); // 15-7 → 15-5
      await _actUntilTitle(tester, _photoManageTitle);
      await _actUntil(tester, () => _photoManageNames(tester).length == left); // 15-5 가 서버 사진으로 다시 그려질 때까지
      await _photoOpenEditor(tester);
      reopenedTiles = _photoTiles(tester);
      reopenedIds = _photoIds(_photoEditorContainer(tester));
    }
    return {
      'ids_open': idsOpen,
      'via': via,
      'ids_swapped': idsSwapped,
      'error': shown,
      'error_text': errorText,
      'title_after_error': titleAfterError,
      'reopened_tiles': reopenedTiles,
      'reopened_ids': reopenedIds,
    };
  }),
  'E-EDGE-03': _session((tester, job) async {
    final face = await _photoFile(job['photo'] as String);
    await _openManage(tester);
    final namesBefore = _photoManageNames(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final asked = <int>[];
    _photoGallery(container, [face], asked);
    final tilesBefore = _photoTiles(tester);
    await _photoAdd(tester, container, asked);
    if (_photoTiles(tester) != tilesBefore + 1) {
      throw E2eBlocked('얼굴 사진이 기기 얼굴 검사에서 빠짐 — 사진 세트 확인');
    }
    await step('cut');
    await _photoTapSave(tester);
    await appears(tester, find.text(_photoNetworkNotice), const Duration(seconds: 30));
    final offline = {
      'off_error': container.read(myPhotosViewModelProvider).errorMessage,
      'off_title': _title(tester),
      'off_tiles': _photoTiles(tester),
    };
    await step('restore');
    final saved = await _photoSaveAndWait(tester, namesBefore);
    return {...offline, 'title': saved.$1, 'names_after': saved.$2};
  }),
};
