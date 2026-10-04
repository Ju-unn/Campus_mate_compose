part of 'area1.dart';

// 영역 1 묶음 2 — 홈 계정 · 탈퇴 · 재동의 · 온보딩 뒷단(04-4 ~ 06-3) · 추천 코드(20 · 20d · 06-4).
// PC 쪽은 e2e/area1_b2.py 의 같은 번호(계정 공장으로 단계를 맞추고 DB 를 본다). E-GATE-03 홈 칸은 area1.dart 의 그 가설이 그대로 본다.

const _withdrawnNotice = '탈퇴한 계정이에요';
const _noCode = '없는 코드예요, 다시 확인해 주세요';
const _notAllowed = '이 코드는 쓸 수 없어요';
const _noteShort = '10자 이상 입력해 주세요';

/// 하단 내비의 탭([label] = 메인 · 오늘 · 커뮤니티 · 대화 · 나).
Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

Finder _textButton(String label) => find.widgetWithText(TextButton, label);

/// 뒤로 가기로 [name] 을 못 벗어나는지 — 라우터에 돌아갈 곳이 없어야 한다.
/// 실제 뒤로 가기(handlePopRoute)는 돌아갈 곳이 없으면 앱을 닫아 버려(SystemNavigator.pop) 시험이 멎는다.
void _stays(WidgetTester tester, String name) {
  must(!GoRouter.of(tester.element(screen(name))).canPop(), '$name 에서 뒤로 갈 곳이 있음');
}

/// 20b 리뷰 시트를 닫는다(뒤로 가기와 같은 pop) → 20d.
Future<void> _closeReviewSheet(WidgetTester tester) async {
  await pumpUntil(tester, find.text('추천으로 연결된 친구'), timeout: const Duration(seconds: 5));
  Navigator.of(tester.element(find.text('추천으로 연결된 친구'))).pop();
  await arrive(tester, '20d', timeout: const Duration(seconds: 10));
}

/// 06-3 에서 자기소개를 내고 화면 20 에 닿는다(초안이 비었으면 한 줄 적는다).
Future<void> _toReferral(WidgetTester tester) async {
  await arrive(tester, '06-3');
  final bio = find.byType(TextFormField);
  if (fieldText(tester, find.descendant(of: bio, matching: find.byType(TextField))).trim().isEmpty) {
    await type(tester, find.descendant(of: bio, matching: find.byType(TextField)), '주말엔 카페에서 책을 읽어요.');
  }
  await tap(tester, button('다음'));
  await arrive(tester, '20', timeout: const Duration(seconds: 10));
}

Finder get _codeField => labeled('추천 코드');

Finder get _confirmCode => find.widgetWithText(ElevatedButton, '코드 확인하기');

bool _codeEnabled(WidgetTester tester) => tester.widget<ElevatedButton>(_confirmCode).onPressed != null;

/// 화면 20 에서 [code] 를 넣고 확인 — 문구 [expect] 가 뜨고 20 에 그대로 있어야 한다.
Future<void> _refused(WidgetTester tester, String code, String expect) async {
  await type(tester, _codeField, code);
  await tap(tester, _confirmCode);
  await pumpUntil(tester, find.text(expect), timeout: const Duration(seconds: 10));
  must(screen('20').evaluate().isNotEmpty, '"$code" 뒤에 20 을 벗어남');
}

Future<void> _skipToAcquisition(WidgetTester tester) async {
  await tap(tester, find.text('건너뛰기')); // 20 의 건너뛰기(글자 버튼)
  await arrive(tester, '20d', timeout: const Duration(seconds: 5));
}

/// 탭할 수 있는 [SelectChip] 들(화면 순서).
List<SelectChip> _chips(WidgetTester tester) => tester.widgetList<SelectChip>(find.byType(SelectChip)).toList();

int _selectedChips(WidgetTester tester) => _chips(tester).where((chip) => chip.isSelected).length;

Future<void> _tapChip(WidgetTester tester, int index) => tap(tester, find.byType(SelectChip).at(index));

/// 05-01 ~ 05-11 의 [count] 문항에 답한다(문항마다 다른 칸).
Future<void> _answer(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    final dots = find.descendant(of: find.byType(TraitSlider), matching: find.byType(GestureDetector)).hitTestable();
    await tester.tap(dots.at(i % 5));
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, button('다음'));
    await wait(tester, const Duration(milliseconds: 400)); // 쪽 넘김 200ms
  }
}

Future<void> _settingsWithdraw(WidgetTester tester) async {
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byTooltip('설정'), timeout: const Duration(seconds: 10));
  await tap(tester, find.byTooltip('설정'));
  await arrive(tester, 'settings', timeout: const Duration(seconds: 5));
  // 설정은 나 탭 위에 쌓인다 — 뒤에 깔린 나 탭 목록이 아니라 설정 화면의 목록을 굴린다.
  final settings = find.ancestor(of: screen('settings'), matching: find.byType(Scaffold)).first;
  await tester.scrollUntilVisible(button('탈퇴하기'), 300,
      scrollable: find.descendant(of: settings, matching: find.byType(Scrollable)).first);
  await tap(tester, button('탈퇴하기'));
  await pumpUntil(tester, find.text('정말 떠나시나요?'), timeout: const Duration(seconds: 5));
  await tap(tester, button('영구 삭제'));
  await pumpUntil(tester, find.text('정말 삭제할까요?'), timeout: const Duration(seconds: 5));
}

final Map<String, Area1Case> _b2Cases = {
  'E-AUTH-07': _session((tester, job) async {
    await arrive(tester, 'home');
    await _settingsWithdraw(tester);
    final tappedAt = DateTime.now().toUtc().toIso8601String();
    await tap(tester, button('정말 영구 삭제'));
    await arrive(tester, 'login', timeout: const Duration(seconds: 15));
    return {'tapped_at': tappedAt};
  }),
  'E-AUTH-08': _session((tester, job) async {
    await arrive(tester, 'suspended');
    await tap(tester, _textButton('탈퇴하기'));
    await pumpUntil(tester, find.text('정지 중에 탈퇴할까요?'), timeout: const Duration(seconds: 5));
    must(find.text('정지 중에 탈퇴하면 다시 가입할 수 없어요').evaluate().isNotEmpty, '정지 중 탈퇴 경고 없음');
    await tap(tester, button('정말 영구 삭제'));
    await arrive(tester, 'login', timeout: const Duration(seconds: 15));
    return null;
  }),
  // 탈퇴한 계정으로 새로 로그인 — 첫 API 가 401 · withdrawn 이라 로그인 화면 + 3초 토스트.
  // 로그인 직전에도 로그인 화면이 잠깐 보이므로(앞 세션을 지움) 토스트가 뜨는 것을 기준으로 잰다.
  'E-AUTH-09': _session((tester, job) async {
    final at = await appears(tester, find.text(_withdrawnNotice), const Duration(seconds: 10));
    must(at != null, '10초 안에 "$_withdrawnNotice" 토스트가 안 나옴');
    must(screen('login').evaluate().isNotEmpty, '토스트가 떴는데 로그인 화면이 아님');
    return {'note': '토스트까지 ${at!.inMilliseconds}ms'};
  }),
  'E-GATE-04': _session((tester, job) async {
    await arrive(tester, 'home');
    await step('home'); // PC 가 status=suspended 로 바꾼다
    await tap(tester, _tab('오늘'));
    final at = await appears(tester, screen('suspended'), const Duration(seconds: 3));
    must(at != null, '3초 안에 정지 안내 화면이 안 나옴');
    _stays(tester, 'suspended');
    return {'note': '${at!.inMilliseconds}ms'};
  }),
  'E-GATE-05': _session(_arriveAt),
  'E-GATE-17': _session((tester, job) async {
    await arrive(tester, 'consent-renew');
    must(find.text('바뀐 내용을 확인하고 다시 동의해 주세요.').evaluate().isNotEmpty, '재동의 설명이 없음');
    return null;
  }),
  // 18 · 19 — 필수 둘만 켜고 동의 → 5초 안에 홈, 04-1 은 한 번도 안 나와야 한다.
  'E-GATE-18': _session(_renewToHome),
  'E-GATE-19': _session(_renewToHome),
  'E-ONB-27': _session((tester, job) async {
    await arrive(tester, '04-4');
    await tap(tester, find.text('강아지상'));
    must(!enabled(tester, '다음'), '얼굴상만 골랐는데 다음이 켜짐');
    await tap(tester, find.widgetWithText(SelectChip, '선한상'));
    must(enabled(tester, '다음'), '인상까지 골랐는데 다음이 꺼짐');
    return null;
  }),
  'E-ONB-28': _session((tester, job) async {
    await arrive(tester, job['expect'] as String);
    for (final (count, on) in [(2, false), (3, true), (5, true)]) {
      while (_selectedChips(tester) < count) {
        await _tapChip(tester, _selectedChips(tester));
      }
      must(enabled(tester, '다음') == on, '$count개에 다음이 ${on ? '꺼짐' : '켜짐'}');
    }
    await _tapChip(tester, 5);
    must(_selectedChips(tester) == 5, '6번째를 눌렀더니 ${_selectedChips(tester)}개');
    return null;
  }),
  'E-ONB-30': _session((tester, job) async {
    await arrive(tester, '05-01');
    await _answer(tester, 9);
    await tap(tester, find.text('무교'));
    await tap(tester, button('다음'));
    await wait(tester, const Duration(milliseconds: 400));
    await tap(tester, find.text('안 한다'));
    await tap(tester, button('다음'));
    await arrive(tester, '05-12', timeout: const Duration(seconds: 20));
    return null;
  }),
  // 첫 켬: 5문항 답하고 끝(PC 가 앱을 죽인다). 다시 켬은 PC 가 expect=05-01 로 본다.
  'E-ONB-31': _session((tester, job) async {
    if (!_fresh(job)) return _arriveAt(tester, job);
    await arrive(tester, '05-01');
    await _answer(tester, 5);
    return null;
  }),
  'E-ONB-33': _session((tester, job) async {
    await arrive(tester, '05-12');
    await step('05-12'); // PC 가 pending 행을 ready 로 바꾼다 — 만드는 중 화면이 5초 간격으로 물어 '완성됐어요' 로 바뀐다
    await pumpUntil(tester, find.text('아바타가 완성됐어요'), timeout: const Duration(seconds: 20));
    await tap(tester, button('다음'));
    await arrive(tester, '06-1', timeout: const Duration(seconds: 10));
    return null;
  }),
  'E-ONB-43': _session((tester, job) async {
    await arrive(tester, '06-1');
    for (final face in ['강아지상', '고양이상', '여우상', '곰상']) {
      await tap(tester, find.text(face));
    }
    final picked = ProviderScope.containerOf(tester.element(screen('06-1')))
        .read(idealConditionsViewModelProvider)
        .preferredAnimalTypes
        .length;
    must(picked == 3, '얼굴상 4개를 눌렀더니 $picked개');
    must(!enabled(tester, '다음'), '인상 0개인데 다음이 켜짐');
    return null;
  }),
  'E-ONB-44': _session((tester, job) async {
    await arrive(tester, '06-1');
    await tap(tester, find.text('강아지상'));
    await tap(tester, find.widgetWithText(SelectChip, '선한상'));
    await tap(tester, find.text('나이는 상관없어요'));
    await tap(tester, find.text('키는 상관없어요'));
    await tap(tester, button('다음'));
    await arrive(tester, '06-2', timeout: const Duration(seconds: 10));
    return null;
  }),
  'E-ONB-46': _session((tester, job) => _note(tester, '가나다라마바사아자', '가나다라마바사아자차')),
  'E-ONB-47': _session((tester, job) => _note(tester, '   가나다라마바사아자   ', '😀' * 10)),
  'E-ONB-48': _session((tester, job) async {
    await arrive(tester, '06-3', timeout: const Duration(seconds: 30));
    final draft = _bioText(tester);
    must(draft.trim().isNotEmpty, '초안 칸이 비어 있음');
    return {'draft': draft};
  }),
  'E-ONB-49': _session((tester, job) async {
    await arrive(tester, '06-2b');
    await tap(tester, _textButton('직접 쓸게요'));
    await arrive(tester, '06-3', timeout: const Duration(seconds: 5));
    must(_bioText(tester).isEmpty, '직접 쓰기인데 칸에 "${_bioText(tester)}"');
    return null;
  }),
  'E-ONB-50': _session((tester, job) async {
    await arrive(tester, '06-3', timeout: const Duration(seconds: 30));
    final draft = _bioText(tester);
    if (!_fresh(job)) must(draft == job['draft'], '다시 연 초안이 다름');
    return {'draft': draft};
  }),
  'E-ONB-51': _session((tester, job) async {
    await arrive(tester, '06-3', timeout: const Duration(seconds: 30));
    final field = find.descendant(of: find.byType(TextFormField), matching: find.byType(TextField));
    for (final text in ['', '   ']) {
      await type(tester, field, text);
      must(!enabled(tester, '다음'), '"$text" 에 다음이 켜짐');
    }
    return null;
  }),
  'E-ONB-52': _session((tester, job) async {
    final watch = Stopwatch()..start();
    await _toReferral(tester);
    return {'note': '20 까지 ${watch.elapsedMilliseconds}ms'};
  }),
  'E-ONB-53': _session(_arriveAt),
  // 첫 켬: 04-4 를 저장해 04-5 가 뜨자마자 끝(PC 가 앱을 죽인다). 다시 켬은 PC 가 expect=04-5 로 본다.
  'E-ONB-54': _session((tester, job) async {
    if (!_fresh(job)) return _arriveAt(tester, job);
    await arrive(tester, '04-4');
    await tap(tester, find.text('강아지상'));
    await tap(tester, find.widgetWithText(SelectChip, '선한상'));
    await tap(tester, button('다음'));
    await arrive(tester, '04-5', timeout: const Duration(seconds: 10));
    return null;
  }),
  // 첫 켬: 갤러리 대신 마스코트 그림 3장을 고르고(올리지 않음) 끝. 다시 켬: 04-2 가 빈 칸으로.
  'E-ONB-55': _session((tester, job) async {
    if (!_fresh(job)) {
      await _arriveAt(tester, job);
      must(find.text('사진 추가').evaluate().length == 4, '다시 켠 04-2 의 빈 칸이 4개가 아님');
      return null;
    }
    await arrive(tester, '04-2');
    final data = await rootBundle.load('assets/images/mascot-male.png');
    final dir = (await getTemporaryDirectory()).path;
    final files = [
      for (var i = 0; i < 3; i++) await File('$dir/e2e-photo-$i.png').writeAsBytes(data.buffer.asUint8List()),
    ];
    final container = ProviderScope.containerOf(tester.element(screen('04-2')));
    container.read(photosViewModelProvider.notifier).pickFromGallery = (limit) async => files.take(limit).toList();
    await tap(tester, find.text('사진 추가').first);
    await wait(tester, const Duration(seconds: 5)); // 압축 · 얼굴 검사
    final kept = container.read(photosViewModelProvider).photos.length;
    if (kept != 3) {
      // 얼굴 검사가 그림을 빼면 이 가설은 사진 세트(묶음 3)가 있어야 한다.
      throw E2eBlocked('고른 3장 중 $kept장만 남음(얼굴 검사) — 사진 세트 필요');
    }
    return null;
  }),
  'E-ONB-56': _session((tester, job) async {
    await arrive(tester, '04-5');
    must(find.byType(AppBottomNav).evaluate().isEmpty, '온보딩 중에 하단 내비가 보임');
    _stays(tester, '04-5');
    return null;
  }),
  'E-ONB-60': _session((tester, job) async {
    await _toReferral(tester);
    await type(tester, _codeField, job['code'] as String);
    await tap(tester, _confirmCode);
    await _closeReviewSheet(tester); // 5초 안 20b 시트 → 닫으면 20d
    return null;
  }),
  // 추천인 폰 — 홈까지 켜서 알림 토큰이 등록되게 둔다. HOME · 코드 입력 · 알림 확인은 PC 가 한다.
  'E-ONB-61': _session((tester, job) async {
    await arrive(tester, 'home');
    await wait(tester, const Duration(seconds: 3));
    return null;
  }),
  'E-ONB-62': _session((tester, job) async {
    await _toReferral(tester);
    final pasted = job['code'] as String;
    await type(tester, _codeField, pasted);
    final shown = fieldText(tester, _codeField);
    must(shown == pasted.trim().toUpperCase(), '칸에 "$shown"(대문자 6자가 아님)');
    await tap(tester, _confirmCode);
    await _closeReviewSheet(tester);
    return null;
  }),
  'E-ONB-63': _session((tester, job) async {
    await _toReferral(tester);
    await type(tester, _codeField, 'K7M2Q');
    must(!_codeEnabled(tester), '5자인데 확인이 켜짐');
    return null;
  }),
  'E-ONB-64': _session((tester, job) async {
    await _toReferral(tester);
    await _refused(tester, job['code'] as String, _noCode);
    return null;
  }),
  'E-ONB-65': _session((tester, job) async {
    await _toReferral(tester);
    await _refused(tester, job['code'] as String, _notAllowed);
    return null;
  }),
  'E-ONB-66': _session((tester, job) async {
    await _toReferral(tester);
    for (final code in (job['codes'] as List).cast<String>()) {
      await _refused(tester, code, _noCode);
    }
    return null;
  }),
  'E-ONB-70': _session((tester, job) async {
    await _toReferral(tester);
    await _skipToAcquisition(tester);
    await tap(tester, _textButton('건너뛰기'));
    await arrive(tester, '06-4', timeout: const Duration(seconds: 5));
    must(find.text('지인 차단').evaluate().isNotEmpty, '"지인 차단" 제목 없음');
    must(button('연락처에서 지인 차단하기').evaluate().isNotEmpty, '"연락처에서 지인 차단하기" 없음');
    await tap(tester, _textButton('건너뛰기'));
    await arrive(tester, 'home', timeout: const Duration(seconds: 10));
    return null;
  }),
  // 첫 켬: 20 에 닿으면 끝. 다시 켬: 5초 안 홈, 20 · 20d · 06-4 는 안 나온다.
  'E-ONB-71': _session((tester, job) async {
    if (_fresh(job)) {
      await _toReferral(tester);
      return null;
    }
    final arrived = await _arriveAt(tester, job);
    for (final name in ['20', '20d', '06-4']) {
      must(screen(name).evaluate().isEmpty, '다시 켰는데 $name 가 보임');
    }
    return arrived;
  }),
  'E-ONB-72': _session((tester, job) async {
    await _toReferral(tester);
    await _skipToAcquisition(tester);
    await tap(tester, find.widgetWithText(SelectChip, '기타'));
    must(!enabled(tester, '시작하기'), '"기타" 빈칸인데 시작하기가 켜짐');
    final other = labeled('어디서 알게 되셨나요?');
    await type(tester, other, '가' * 31);
    must(fieldText(tester, other).length == 30, '칸에 ${fieldText(tester, other).length}자');
    await tap(tester, button('시작하기'));
    await arrive(tester, '06-4', timeout: const Duration(seconds: 10));
    return null;
  }),
  'E-ONB-73': _session((tester, job) async {
    await _toReferral(tester);
    await _skipToAcquisition(tester);
    await tap(tester, find.widgetWithText(SelectChip, '에브리타임'));
    await tap(tester, button('시작하기'));
    await arrive(tester, '06-4', timeout: const Duration(seconds: 5));
    await tap(tester, _textButton('건너뛰기'));
    await arrive(tester, 'home', timeout: const Duration(seconds: 10));
    return null;
  }),
};

Future<Map<String, Object?>?> _renewToHome(WidgetTester tester, Map<String, dynamic> job) async {
  await arrive(tester, 'consent-renew');
  await _consentRow(tester, '이용약관');
  await _consentRow(tester, '개인정보 수집·이용');
  await tap(tester, button(_consentCta));
  final watch = Stopwatch()..start();
  var saw041 = false;
  while (screen('home').evaluate().isEmpty || find.byType(AppBottomNav).evaluate().isEmpty) {
    must(watch.elapsed < const Duration(seconds: 5), '5초 안에 홈이 안 나옴');
    await tester.pump(const Duration(milliseconds: 100));
    saw041 |= screen('04-1').evaluate().isNotEmpty;
  }
  must(!saw041, '재동의 뒤 04-1 이 보임');
  return {'note': '${watch.elapsedMilliseconds}ms'};
}

String _bioText(WidgetTester tester) =>
    fieldText(tester, find.descendant(of: find.byType(TextFormField), matching: find.byType(TextField)));

/// 06-2a — [short] 는 "다음" 뒤 빨간 문구로 막히고, [ok] 는 저장돼 06-2b(또는 06-3)로 간다.
Future<Map<String, Object?>?> _note(WidgetTester tester, String short, String ok) async {
  await arrive(tester, '06-2a');
  final field = find.descendant(of: find.byType(TextFormField), matching: find.byType(TextField));
  await type(tester, field, short);
  await tap(tester, button('다음'));
  // 같은 글자가 타이핑 중엔 회색 안내로도 보이므로 빨간 것만 오류로 센다.
  await pumpUntil(tester, find.byWidgetPredicate((w) => w is Text && w.data == _noteShort && w.style?.color == AppColors.error),
      timeout: const Duration(seconds: 5));
  must(screen('06-2a').evaluate().isNotEmpty, '"$short" 로 06-2a 를 벗어남');
  await type(tester, field, ok);
  await tap(tester, button('다음'));
  // 저장되면 06-2b(초안 만드는 중), 빠르면 바로 06-3.
  await pumpUntil(tester, find.byWidgetPredicate((w) => w is Text && (w.data == screens['06-2b'] || w.data == screens['06-3'])),
      timeout: const Duration(seconds: 10));
  return {'saved': ok};
}
