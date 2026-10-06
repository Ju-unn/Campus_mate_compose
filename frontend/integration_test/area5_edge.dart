part of 'area5.dart';

// 영역 5 경계 7개(묶음 area5-edge — 폰 A: E-EDGE-01 · 11 · 15 · 19, B에뮬: 21 · 24 · 25). PC 쪽은 e2e/area5_edge.py 의 같은 번호 —
// 계정 · DB 를 준비하고, 앱이 멈춘 사이 망(비행기 모드 · 에뮬 지연 · 패킷 버림) · 계정(삭제) · 프로세스(kill)를 바꾸고 판정한다.
// 앱은 화면을 열어 고치고 누르고 본 것을 Map 으로 말한다(문구는 사람이 읽는 글자 그대로, 못 본 것은 null).
// 멈춤이 여럿인 가설은 `화면:일` 이름으로 멈추고 마지막에 `end` 에서 멈춘다(PC 의 _walk). 누르기는 버튼 가운데가 아니라 안의 글자를 누른다(#282) —
// 로딩 중 두 번째 누름만 글자가 스피너로 바뀌어 버튼 위젯을 누른다. 이 파일에 탈퇴 · 삭제 · 나가기 버튼을 누르는 줄은 없다.
// 이 파일의 이름은 모두 `_ed` 로 시작한다. 편집 화면 도우미는 area5_act.dart(`_act…`) · area5_photo.dart(`_photo…`)의 것을 그대로 쓴다.
// 이 파일은 클라우드 세션에서 Flutter 없이 썼다 — `flutter analyze` · 기기 실행은 아직이다.

const _edNetwork = '네트워크 연결을 확인해 주세요'; // common/failure.dart NetworkFailure
const _edScreens = ['15-6', '15c', '06-1', 'tag', '15-7']; // e2e/area5_edge.py SCREENS 와 같은 차례
const _edArrival = {
  '15-6': _actManageTitle,
  '15c': _actManageTitle,
  '06-1': _actManageTitle,
  'tag': _actBioTitle,
  '15-7': _actManageTitle,
};
const _edTitles = {
  '15-6': _actBasicTitle,
  '15c': _actBioTitle,
  '06-1': _actIdealTitle,
  'tag': '관심사 수정',
  '15-7': _photoEditTitle,
};
const _edSaveWait = Duration(seconds: 40); // 2초 지연 망에서도 저장 · 다시 읽기가 끝나는 한도

/// "저장" AppButton — 로딩 중에는 글자가 스피너로 바뀌어 글자로 못 찾으므로 라벨로 찾는다.
Finder get _edSaveButton => find.byWidgetPredicate((w) => w is AppButton && w.label == _actSave);

bool _edLoading(WidgetTester tester) => _has(_edSaveButton) && tester.widget<AppButton>(_edSaveButton.last).isLoading;

/// "저장" 안의 글자를 누른다.
Future<void> _edTapSave(WidgetTester tester) async {
  final label = find.descendant(of: _edSaveButton, matching: find.text(_actSave));
  must(_has(label), '저장 버튼 글자를 못 찾음 — 화면 ${_title(tester)}');
  await tester.ensureVisible(label.last);
  await tester.pump();
  await tester.tap(label.last);
}

/// 15-5 에서 [screen] 을 연다.
Future<void> _edEnter(WidgetTester tester, String screen) async {
  switch (screen) {
    case '15-6':
      await _actEnterBasic(tester);
    case '15c':
      await _actEnterBio(tester);
    case '06-1':
      await _actEnterIdeal(tester);
    case 'tag':
      await _actEnterBio(tester);
      await tap(tester, find.text(_actEdit).first); // 관심사 섹션의 "수정 ›"
      await pumpUntil(tester, find.byType(TagPickerScreen));
      await wait(tester, const Duration(milliseconds: 500));
    case '15-7':
      await _photoOpenEditor(tester);
  }
}

/// [screen] 의 값을 하나 고친다(저장은 안 함). 15-7 은 첫 · 둘째 칸을 맞바꾼다 — 새 파일이 없어 Vision 을 안 부른다.
Future<void> _edEdit(WidgetTester tester, String screen, Map<String, dynamic> job) async {
  switch (screen) {
    case '15-6':
      if (job['nickname'] case final String nickname) await _actProbeNickname(tester, nickname);
      await type(tester, _actHeightField, job['height'] as String);
      await wait(tester, const Duration(milliseconds: 400));
    case '15c':
      await type(tester, find.byType(TextField).first, job['bio'] as String);
    case '06-1':
      await tap(tester, find.text(_ageIgnore));
    case 'tag':
      await tap(tester, _actChip(job['extra'] as String));
    case '15-7':
      _photoEditorContainer(tester).read(myPhotosViewModelProvider.notifier).swapPhotos(0, 1);
      await tester.pump(const Duration(milliseconds: 300));
  }
  FocusManager.instance.primaryFocus?.unfocus(); // 키보드가 저장 버튼을 가리지 않게
  await wait(tester, const Duration(milliseconds: 400));
}

/// 고친 값이 화면에 그대로 있는지 — [edited] 는 고친 직후 [_edValue] 로 읽은 값.
Object? _edValue(WidgetTester tester, String screen) => switch (screen) {
      '15-6' => fieldText(tester, _actHeightField),
      '15c' => fieldText(tester, find.byType(TextField).first),
      '06-1' => _has(find.byType(Checkbox)) ? tester.widget<Checkbox>(find.byType(Checkbox).first).value : null,
      'tag' => _actSelectedChips(tester).join('|'),
      '15-7' => _photoIds(_photoEditorContainer(tester)).join('|'),
      _ => null,
    };

/// 저장이 끝나 [screen] 의 도착 화면이 된 뒤 15-5 로 거슬러 간다(태그는 15c 에 닿는다).
Future<String?> _edSavedAndBack(WidgetTester tester, String screen) async {
  final title = await _actUntilTitle(tester, _edArrival[screen]!, timeout: _edSaveWait);
  await _returnTo(tester, _actManageTitle);
  await _actManageLoaded(tester);
  await wait(tester, const Duration(milliseconds: 500));
  return title;
}

/// 망이 끊긴 채 저장한 뒤 — 문구 · 버튼 위인지 · 값 · 화면.
Future<Map<String, Object?>> _edOffline(WidgetTester tester, String screen, Object? edited) async {
  final error = find.text(_edNetwork);
  final seen = await appears(tester, error, const Duration(seconds: 15)) != null;
  final above = seen && _has(_edSaveButton) && tester.getRect(error.first).bottom <= tester.getRect(_edSaveButton.last).top;
  return {
    'error': seen ? _edNetwork : null,
    'error_above': above,
    'kept': _edValue(tester, screen) == edited,
    'stayed': _title(tester),
  };
}

/// 알림으로 연 앱의 지금 화면 — 화면에 그려진(offstage 아닌) 것만 본다.
String? _edWhere(WidgetTester tester) {
  if (_has(find.byType(ChatRoomScreen)) || _has(find.byType(ReceivedReviewsScreen))) return 'stayed';
  if (_has(find.byType(ConversationsScreen))) return 'conversations';
  if (_has(find.byType(MyProfileScreen))) return 'me';
  return _title(tester);
}

/// 알림 누름으로 콜드 스타트한 앱 — 로그아웃 · 새 로그인을 하지 않는다(저장된 세션 그대로). [screen] 이 뜨면 `opened` 에서 멈추고,
/// PC 가 시스템 뒤로를 보낸 뒤 go 를 넣으면 도착 화면을 말한다.
Future<Map<String, Object?>> _edTapped(WidgetTester tester, Type screen) async {
  final opened = await appears(tester, find.byType(screen), const Duration(seconds: 30)) != null;
  if (!opened) return {'opened': false, 'where': _edWhere(tester)};
  await wait(tester, const Duration(seconds: 1));
  await step('opened');
  await wait(tester, const Duration(seconds: 2)); // 뒤로가 옮긴 화면이 자리를 잡게
  return {'opened': true, 'where': _edWhere(tester)};
}

final Map<String, Area1Case> area5CasesEdge = {
  // 다섯 화면마다: 고치고 → 멈춤(PC 가 비행기 모드) → 저장 → 문구 · 값 · 화면을 읽고 → 멈춤(PC 가 망을 되돌림) → 다시 저장 → 15-5 로.
  'E-EDGE-01': _session((tester, job) async {
    await _openManage(tester);
    final walks = <Map<String, Object?>>[];
    for (final screen in _edScreens) {
      await _edEnter(tester, screen);
      await _edEdit(tester, screen, job);
      final edited = _edValue(tester, screen);
      await step('$screen:edited');
      await _edTapSave(tester);
      final offline = await _edOffline(tester, screen, edited);
      await step('$screen:failed', timeout: const Duration(minutes: 3));
      await _edTapSave(tester);
      walks.add({'screen': screen, ...offline, 'saved_title': await _edSavedAndBack(tester, screen)});
    }
    await step('end');
    return {'walks': walks};
  }),

  // 15-6 을 연 채 멈춘 사이 PC 가 auth 사용자를 지운다 → 키를 고쳐 저장 → 02 와 알림.
  'E-EDGE-11': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    await step('opened');
    await type(tester, _actHeightField, job['height'] as String);
    await wait(tester, const Duration(milliseconds: 400));
    await _edTapSave(tester);
    final (login, notice) = await _twoLoginNotice(tester);
    return {'login': login, 'notice': notice, 'stayed': _has(find.byType(BasicInfoEditScreen))};
  }),

  // phase login: 홈까지(기기 토큰이 올라가게). chat · review: 알림으로 콜드 스타트한 판 — 세션을 지우지 않는다.
  'E-EDGE-15': (tester, job) => switch (job['phase']) {
        'chat' => _edTapped(tester, ChatRoomScreen),
        'review' => _edTapped(tester, ReceivedReviewsScreen),
        _ => _session((tester, job) async {
            await arrive(tester, 'home');
            await wait(tester, const Duration(seconds: 3)); // 기기 토큰 등록
            return null;
          })(tester, job),
      },

  // phase press: 저장을 누르자마자 답을 기다리지 않는 멈춤 말 → PC 가 0.3초 뒤 죽인다. phase after: 저장된 세션 그대로 다시 켜 15 · 15-5 를 읽는다.
  'E-EDGE-19': (tester, job) async {
    final photo = job['part'] == 'photo';
    if (job['phase'] == 'after') {
      if (!photo) {
        await _openMe(tester);
        await wait(tester, const Duration(seconds: 1));
        final name = find.descendant(
          of: find.byType(ProfileHero),
          matching: find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == AppTypography.headline.fontSize),
        );
        return {'name_line': _textOf(tester, name)};
      }
      await _openManage(tester);
      await _actUntil(tester, () => _photoManageNames(tester).isNotEmpty);
      return {'photos': _photoManageNames(tester)};
    }
    return _session((tester, job) async {
      await _openManage(tester);
      await _edEnter(tester, photo ? '15-7' : '15-6');
      if (photo) {
        await _edEdit(tester, '15-7', job);
      } else {
        await _actProbeNickname(tester, job['nickname'] as String);
      }
      await _edTapSave(tester);
      await say({'step': 'pressed'});
      await wait(tester, const Duration(seconds: 30)); // 여기서 죽는다 — 안 죽으면 PC 는 이미 끝냈다
      return null;
    })(tester, job);
  },

  // 2초 지연 망(PC 가 adb emu) — 화면마다 0.1초 간격으로 "저장" 을 두 번. 두 번째가 로딩 중 버튼에 막혔는지와 도착 화면.
  'E-EDGE-21': _session((tester, job) async {
    await _openManage(tester);
    final walks = <Map<String, Object?>>[];
    for (final screen in _edScreens) {
      await _edEnter(tester, screen);
      await _edEdit(tester, screen, job);
      await step('$screen:start');
      await _edTapSave(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final blocked = _edLoading(tester);
      if (_has(_edSaveButton)) await tester.tap(_edSaveButton.last, warnIfMissed: false);
      walks.add({'screen': screen, 'second_blocked': blocked, 'saved_title': await _edSavedAndBack(tester, screen)});
      await step('$screen:done');
    }
    await step('end');
    return {'walks': walks};
  }),

  // 느린 망(edge + gprs) — 15-7 의 칸을 비우고 얼굴 사진을 네 번 골라 저장. 끝날 때까지 프레임마다 버튼이 로딩인지, 로딩 중 다시 누름이 막혔는지.
  'E-EDGE-24': _session((tester, job) async {
    await _openManage(tester);
    await _photoOpenEditor(tester);
    final container = _photoEditorContainer(tester);
    final notifier = container.read(myPhotosViewModelProvider.notifier);
    while (container.read(myPhotosViewModelProvider).photos.isNotEmpty) {
      notifier.removePhoto(0);
    }
    await tester.pump(const Duration(milliseconds: 300));
    final file = await _photoFile(job['photo'] as String);
    await _photoPick(tester, container, List.filled(job['count'] as int, file));
    await step('15-7:start');
    await _edTapSave(tester);
    var kept = true;
    bool? extraBlocked;
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(minutes: 3) && _has(find.byType(MyPhotosScreen))) {
      await tester.pump(const Duration(milliseconds: 100));
      if (!_has(find.byType(MyPhotosScreen))) break;
      final loading = _edLoading(tester);
      kept &= loading || !_has(_edSaveButton);
      if (extraBlocked == null && loading) {
        extraBlocked = tester.widget<AppButton>(_edSaveButton.last).isLoading;
        await tester.tap(_edSaveButton.last, warnIfMissed: false);
      }
    }
    final title = await _actUntilTitle(tester, _photoManageTitle);
    await _actUntil(tester, () => _photoManageNames(tester).length == job['count'], timeout: const Duration(seconds: 30));
    await step('15-7:done');
    await step('end');
    return {'loading_kept': kept, 'extra_tap_blocked': extraBlocked ?? false, 'title': title, 'photos': _photoManageNames(tester).length};
  }),

  // 응답 없는 망(PC 가 iptables 로 패킷 버림) — 15-6 키를 고쳐 저장하고 [watch]초 동안 지켜본 뒤 그때의 로딩 · 문구 · 화면.
  'E-EDGE-25': _session((tester, job) async {
    await _openManage(tester);
    await _actEnterBasic(tester);
    await type(tester, _actHeightField, job['height'] as String);
    await wait(tester, const Duration(milliseconds: 400));
    FocusManager.instance.primaryFocus?.unfocus();
    await step('15-6:ready');
    await _edTapSave(tester);
    final watch = Stopwatch()..start();
    while (watch.elapsed < Duration(seconds: job['watch'] as int)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final result = {
      'loading_at_end': _edLoading(tester),
      'error': _has(find.text(_edNetwork)) ? _edNetwork : null,
      'title': _title(tester),
      'waited_ms': watch.elapsedMilliseconds,
    };
    await step('15-6:watched');
    await step('end');
    return result;
  }),
};
