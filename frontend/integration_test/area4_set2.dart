part of 'area4.dart';

// 영역 4 SET 2차 — FAQ 21 · 친구 초대 16i · 하트 모으기 입구 · 로그아웃 16g · 탈퇴 16c. PC 쪽은 e2e/area4_set2.py 의 같은 번호.
// 화면 글자는 시나리오가 아니라 지금 화면 코드(frontend/lib/faq · referral · account · core/auth)에서 옮겼다.
// 앱이 안 보이는 사이(공유 창)에는 프레임이 안 돌 수 있어, 그동안은 우편함(step)만 부른다.

const _faqHint = '궁금한 내용을 검색해 보세요';
const _inviteDescription = '친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.';
const _copied = '코드를 복사했어요';
const _faqMail = 'appmailerl4538@gmail.com';
const _logoutDescription = '다시 로그인하려면 학교 이메일로 인증 코드를 한 번 더 받아야 해요.';
const _withdrawnToast = '탈퇴한 계정이에요';

List<String> _strings(Object? value) => (value as List).cast<String>();

/// 홈 → 나 탭 → (옵션 [beforeGear]) → 톱니바퀴 → 설정 16. 망을 끊고 설정을 처음 여는 가설용으로 톱니바퀴 직전에 멈출 수 있다.
Future<void> _openSettingsAfter(WidgetTester tester, Future<void> Function() beforeGear) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byIcon(AppIcons.settings));
  await beforeGear();
  await tap(tester, find.byIcon(AppIcons.settings));
  await arrive(tester, 'settings');
}

Future<void> _openFaq(WidgetTester tester) => _openFromSettings(tester, '자주 묻는 질문', '자주 묻는 질문');

Finder get _faqRowsList => find.descendant(of: find.byKey(const ValueKey('faq-list')), matching: find.byType(ListView));

/// 21 목록의 위젯 목록(화면 밖 줄도 들어 있다). 결과가 0개면 ListView 가 없다.
List<Widget> _faqChildren(WidgetTester tester) {
  if (_faqRowsList.evaluate().isEmpty) return const [];
  return (tester.widget<ListView>(_faqRowsList).childrenDelegate as SliverChildListDelegate).children;
}

/// 지금 21 에 있는 질문 줄의 질문 글자(위 → 아래). `_FaqRow` 는 비공개 클래스지만 `item` 은 공개 칸이다.
List<String> _faqQuestions(WidgetTester tester) => [
      for (final child in _faqChildren(tester))
        if (child.runtimeType.toString() == '_FaqRow') (child as dynamic).item.question as String,
    ];

/// 검색 중에만 있는 묶음 머리글(탭 글자와 같은 글자의 Text).
List<String> _faqHeaders(WidgetTester tester, List<String> labels) => [
      for (final child in _faqChildren(tester))
        if (child is Text && labels.contains(child.data)) child.data!,
    ];

/// 탭 줄이 있는지 — 탭 줄은 21 안의 가로 스크롤 하나뿐이다.
bool _faqTabsShown() => find
    .descendant(
      of: find.byType(FaqScreen),
      matching: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
    )
    .evaluate()
    .isNotEmpty;

Finder get _faqSearch => input(_faqHint);

/// [questions] 가 21 에 그 순서로 나타날 때까지(내려받기 · 펼침 애니메이션 · 검색 반영을 기다린다).
Future<void> _seeQuestions(WidgetTester tester, List<String> questions, String label,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final watch = Stopwatch()..start();
  while (_faqQuestions(tester).join('\u0001') != questions.join('\u0001')) {
    must(watch.elapsed < timeout, '$label: 질문 ${_faqQuestions(tester)}(기대 $questions)');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _search(WidgetTester tester, String text) async {
  await type(tester, _faqSearch, text);
  await wait(tester, const Duration(milliseconds: 400));
}

/// 설정 줄이 없어질 때까지(받는 중에는 보이고 못 받고 저장본도 없으면 숨는다).
Future<void> _rowGone(WidgetTester tester, String row, {Duration timeout = const Duration(seconds: 40)}) async {
  final watch = Stopwatch()..start();
  while (find.text(row).evaluate().isNotEmpty) {
    must(watch.elapsed < timeout, '"$row" 줄이 ${timeout.inSeconds}초가 지나도 안 사라짐');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _faqCacheFile(void Function(File file) use) async {
  use(File('${(await getApplicationSupportDirectory()).path}/faq_cache.json'));
}

Finder get _inviteSheet => find.byType(InviteFriendsSheet);

Finder _inSheet(String text) => find.descendant(of: _inviteSheet, matching: find.text(text));

Future<void> _openInvite(WidgetTester tester, {required String code}) async {
  await _openSettings(tester);
  await _reveal(tester, find.text('친구 초대'));
  await tap(tester, find.text('친구 초대'));
  await pumpUntil(tester, _inSheet(_inviteDescription));
  await pumpUntil(tester, _inSheet(code), timeout: const Duration(seconds: 15));
}

Future<void> _settingsButton(WidgetTester tester, String label) async {
  final settings = find.ancestor(of: screen('settings'), matching: find.byType(Scaffold)).first;
  await tester.scrollUntilVisible(button(label), 300,
      scrollable: find.descendant(of: settings, matching: find.byType(Scrollable)).first);
  await tap(tester, button(label));
}

Future<void> _confirmLogout(WidgetTester tester) async {
  await _reveal(tester, find.text('로그아웃'));
  await tap(tester, find.text('로그아웃'));
  await pumpUntil(tester, find.text('로그아웃할까요?'), timeout: const Duration(seconds: 5));
  await tap(tester, find.widgetWithText(SafetySheetButton, '로그아웃'));
}

/// 망이 끊긴 사이 아바타 · 카드 사진을 늦게 받으려다 난 SocketException 은 화면에 안 보이는 로그다(폰 첫 실행 10-04, SET-02).
/// 끝에서 프레임 오류로 치지 않게 비운다 — 그 밖의 오류는 그대로 실패.
void _forgiveOfflineNoise(WidgetTester tester) {
  for (var error = tester.takeException(); error != null; error = tester.takeException()) {
    if (!'$error'.contains('SocketException')) throw TestFailure('$error');
  }
}

final Map<String, Area1Case> _set2Cases = {
  'E-SET-02': _session((tester, job) async {
    await _faqCacheFile((file) {
      if (file.existsSync()) file.deleteSync(); // 새로 설치한 것과 같다 — 저장본 없음
    });
    await _openSettingsAfter(tester, () => step('cut'));
    await _rowGone(tester, '자주 묻는 질문');
    await wait(tester, const Duration(seconds: 2));
    // FAQ 줄이 있을 자리의 이웃(연락처 차단 · 이용약관)이 둘 다 그려진 채로 그 사이에 줄이 없어야 한다.
    await _reveal(tester, find.text('이용약관'));
    must(find.text('연락처 차단').evaluate().isNotEmpty && find.text('이용약관').evaluate().isNotEmpty, '이웃 줄이 안 그려져 확인할 수 없음');
    must(find.text('자주 묻는 질문').evaluate().isEmpty, '줄이 다시 나타남');
    for (final row in _settingsRows.where((r) => r != '자주 묻는 질문')) {
      await _reveal(tester, find.text(row));
    }
    _forgiveOfflineNoise(tester);
    return null;
  }),
  'E-SET-03': _session((tester, job) async {
    if (job['phase'] == 'cache') {
      await _openFaq(tester);
      await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
      final seconds = Stopwatch()..start();
      var saved = false;
      while (!saved) {
        await _faqCacheFile((file) => saved = file.existsSync() && file.lengthSync() > 2);
        must(seconds.elapsed < const Duration(seconds: 15), '15초 안에 FAQ 저장본이 안 생김');
        await tester.pump(const Duration(milliseconds: 200));
      }
      return null;
    }
    await _openSettingsAfter(tester, () => step('cut'));
    await pumpUntil(tester, find.text('자주 묻는 질문'), timeout: const Duration(seconds: 40));
    await tap(tester, find.text('자주 묻는 질문'));
    await pumpUntil(tester, _screenTitle('자주 묻는 질문'));
    await _seeQuestions(tester, _strings(job['questions']), '저장본');
    _forgiveOfflineNoise(tester);
    return null;
  }),
  'E-SET-44': _session((tester, job) async {
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    for (final label in _strings(job['labels'])) {
      must(find.text(label).evaluate().isNotEmpty, '탭 "$label" 이 없음');
    }
    must(find.text(_faqHint).evaluate().isNotEmpty, '검색칸 안내 "$_faqHint" 가 없음');
    await _seeQuestions(tester, _strings(job['questions']), '첫 탭');
    return null;
  }),
  'E-SET-45': _session((tester, job) async {
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    final expected = (job['expected'] as Map).map((k, v) => MapEntry(k as String, _strings(v)));
    for (final entry in expected.entries) {
      await tap(tester, find.text(entry.key));
      await _seeQuestions(tester, entry.value, '탭 ${entry.key}');
    }
    return null;
  }),
  'E-SET-46': _session((tester, job) async {
    final questions = _strings(job['questions']), answers = _strings(job['answers']);
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    int open() => [for (final a in answers) if (find.text(a).evaluate().isNotEmpty) a].length;
    await tap(tester, find.text(questions[0]));
    await wait(tester, const Duration(milliseconds: 500));
    must(find.text(answers[0]).evaluate().isNotEmpty && open() == 1, '1번 질문만 펼쳐져야 함(펼친 답 ${open()}개)');
    await tap(tester, find.text(questions[1]));
    await wait(tester, const Duration(milliseconds: 500));
    must(find.text(answers[1]).evaluate().isNotEmpty && find.text(answers[0]).evaluate().isEmpty, '2번만 펼쳐지고 1번은 접혀야 함');
    await tap(tester, find.text(questions[1]));
    await wait(tester, const Duration(milliseconds: 500));
    must(open() == 0, '다시 누르면 접혀야 함(펼친 답 ${open()}개)');
    return null;
  }),
  'E-SET-47': _session((tester, job) async {
    final answer = job['answer'] as String;
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    await tap(tester, find.text(job['question'] as String));
    await wait(tester, const Duration(milliseconds: 500));
    must(find.text(answer).evaluate().isNotEmpty, '질문을 눌렀는데 답이 안 펼쳐짐');
    await tap(tester, find.text(job['other_tab'] as String));
    await wait(tester, const Duration(milliseconds: 500));
    must(find.text(answer).evaluate().isEmpty, '탭을 바꿨는데 펼친 답이 남음');
    return null;
  }),
  'E-SET-48': _session((tester, job) async {
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    await _search(tester, job['needle'] as String);
    final expected = _strings(job['expected']);
    await _seeQuestions(tester, expected, '검색 "${job['needle']}"');
    must(!_faqTabsShown(), '검색 중인데 탭 줄이 보임');
    final headers = _faqHeaders(tester, ['카드·매칭', '하트·결제', '사진·프로필', '지인 리뷰', '안전·신고', '계정']);
    must(headers.join(',') == _strings(job['headers']).join(','), '묶음 머리글 $headers(기대 ${job['headers']})');
    return null;
  }),
  'E-SET-49': _session((tester, job) async {
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    for (final variant in (job['variants'] as List).cast<Map>()) {
      await _search(tester, variant['text'] as String);
      await _seeQuestions(tester, _strings(variant['expected']), '검색 "${variant['text']}"');
    }
    return null;
  }),
  'E-SET-50': _session((tester, job) async {
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    await _search(tester, '   ');
    must(_faqTabsShown(), '공백만 넣었는데 탭 줄이 사라짐');
    await _seeQuestions(tester, _strings(job['questions']), '고른 탭 그대로');
    return null;
  }),
  'E-SET-51': _session((tester, job) async {
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    await _search(tester, job['needle'] as String);
    await pumpUntil(tester, find.text('찾는 질문이 없어요'), timeout: const Duration(seconds: 5));
    for (final text in ['다른 말로 검색하거나', _faqMail, '으로', '물어봐 주세요']) {
      must(find.text(text).evaluate().isNotEmpty, '빈 화면에 "$text" 가 없음');
    }
    return null;
  }),
  'E-SET-54': _session((tester, job) async {
    await _openFaq(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
    await tap(tester, find.text(job['tab'] as String));
    await _seeQuestions(tester, _strings(job['after_clear']), '계정 탭');
    await _search(tester, job['needle'] as String);
    must(!_faqTabsShown(), '검색 중인데 탭 줄이 보임');
    await tap(tester, find.byTooltip('검색어 지우기'));
    await wait(tester, const Duration(milliseconds: 400));
    must(fieldText(tester, _faqSearch) == '', '✕ 를 눌렀는데 검색칸이 안 비워짐');
    must(_faqTabsShown(), '✕ 를 눌렀는데 탭 줄이 안 돌아옴');
    await _seeQuestions(tester, _strings(job['after_clear']), '고른 탭으로 돌아감');
    return null;
  }),
  'E-SET-58': _session((tester, job) async {
    await _openInvite(tester, code: job['code'] as String);
    must(_inSheet('친구 초대').evaluate().isNotEmpty, '시트 제목 "친구 초대" 가 없음');
    return null;
  }),
  'E-SET-59': _session((tester, job) async {
    final code = job['code'] as String;
    await _openInvite(tester, code: code);
    await tap(tester, _inSheet('복사'));
    await pumpUntil(tester, find.text(_copied), timeout: const Duration(seconds: 3));
    final clip = (await Clipboard.getData('text/plain'))?.text;
    must(clip == code, '클립보드 "$clip"(기대 "$code")');
    await wait(tester, const Duration(seconds: 3, milliseconds: 500));
    must(find.text(_copied).evaluate().isEmpty, '3초가 지났는데 토스트가 남음');
    return null;
  }),
  'E-SET-60': _session((tester, job) async {
    await _openInvite(tester, code: job['code'] as String);
    final share = _inSheet('공유하기');
    must(share.evaluate().isNotEmpty, '못 찾음: 공유하기');
    await tester.ensureVisible(share.last);
    await tester.pump();
    await tester.tap(share.last); // 누른 뒤 pump 하지 않는다 — 공유 창이 뜨면 프레임이 멎을 수 있다
    await step('shared'); // PC 가 공유 창과 초대 글을 확인하고 뒤로 가기로 닫는다
    await wait(tester, const Duration(seconds: 2));
    must(_inviteSheet.evaluate().isNotEmpty, '공유 창을 닫은 뒤 초대 시트가 사라짐');
    return null;
  }),
  'E-SET-61': _session((tester, job) async {
    final code = job['code'] as String;
    await _openSettings(tester);
    await _reveal(tester, find.text('친구 초대'));
    await step('cut');
    await tap(tester, find.text('친구 초대'));
    await pumpUntil(tester, _inSheet(_inviteDescription));
    if (await appears(tester, _inSheet(code), const Duration(seconds: 4)) != null) {
      throw E2eBlocked('코드를 이미 받아 둔 상태 — 오류 화면을 못 만듦');
    }
    await pumpUntil(tester, _inSheet('다시 시도'), timeout: const Duration(seconds: 20));
    await step('restore');
    await tap(tester, _inSheet('다시 시도'));
    await pumpUntil(tester, _inSheet(code), timeout: const Duration(seconds: 30));
    return null;
  }),
  'E-SET-62': _session((tester, job) async {
    await _openInvite(tester, code: job['code'] as String);
    await tap(tester, _inSheet('닫기'));
    await wait(tester, const Duration(seconds: 1));
    must(_inviteSheet.evaluate().isEmpty, '닫기를 눌렀는데 시트가 남음');
    must(screen('settings').evaluate().isNotEmpty, '설정 화면으로 돌아오지 않음');
    return null;
  }),
  'E-SET-63': _session((tester, job) async {
    await _openFromSettings(tester, '무료로 하트 모으기', '무료로 하트 모으기');
    return null;
  }),
  'E-SET-64': _session((tester, job) async {
    await _openSettings(tester);
    await _reveal(tester, find.text('로그아웃'));
    await tap(tester, find.text('로그아웃'));
    await pumpUntil(tester, find.text('로그아웃할까요?'), timeout: const Duration(seconds: 5));
    must(find.text(_logoutDescription).evaluate().isNotEmpty, '시트 설명이 다름');
    await tap(tester, find.widgetWithText(SafetySheetButton, '취소'));
    await wait(tester, const Duration(seconds: 1));
    must(find.text('로그아웃할까요?').evaluate().isEmpty, '취소했는데 시트가 남음');
    must(screen('settings').evaluate().isNotEmpty, '설정 화면이 아님');
    must(Supabase.instance.client.auth.currentSession != null, '취소했는데 세션이 사라짐');
    return null;
  }),
  'E-SET-65': _session((tester, job) async {
    await _openSettings(tester);
    await step('ready'); // PC 가 기기 토큰이 서버에 올라온 것을 확인한다
    final tapped = Stopwatch()..start();
    await _confirmLogout(tester);
    await arrive(tester, 'login', timeout: const Duration(seconds: 15));
    return {'note': '로그인 화면까지 ${tapped.elapsedMilliseconds}ms'};
  }),
  'E-SET-66': _session((tester, job) async {
    final nick = job['nick'] as String;
    Future<void> visit() async {
      for (final label in ['오늘', '대화', '나']) {
        await tap(tester, _tab(label));
        await wait(tester, const Duration(seconds: 2));
      }
    }

    await arrive(tester, 'home');
    await visit();
    must(find.textContaining(nick).evaluate().isNotEmpty, '앞 계정 닉네임 "$nick" 이 나 탭에 안 보여 비교할 수 없음');
    await tap(tester, find.byIcon(AppIcons.settings));
    await arrive(tester, 'settings');
    await _confirmLogout(tester);
    await arrive(tester, 'login', timeout: const Duration(seconds: 15));
    await signIn(job['second'] as String);
    await arrive(tester, 'home', timeout: const Duration(seconds: 40));
    for (final label in ['오늘', '대화', '나']) {
      await tap(tester, _tab(label));
      await wait(tester, const Duration(seconds: 2));
      must(find.textContaining(nick).evaluate().isEmpty, '$label 탭에 앞 계정 닉네임 "$nick" 이 남음');
    }
    return null;
  }),
  'E-SET-68': _session((tester, job) async {
    await _openSettings(tester);
    await step('cut');
    await _confirmLogout(tester);
    await arrive(tester, 'login', timeout: const Duration(seconds: 30));
    must(find.text(const UnknownFailure().toDisplayMessage()).evaluate().isEmpty, '오류 문구가 보임');
    return null;
  }),
  'E-SET-69': _session((tester, job) async {
    await _openSettings(tester);
    await _settingsButton(tester, '탈퇴하기');
    await pumpUntil(tester, find.text('정말 떠나시나요?'), timeout: const Duration(seconds: 5));
    await tap(tester, find.text('일시중지'));
    await wait(tester, const Duration(seconds: 1));
    must(find.text('정말 떠나시나요?').evaluate().isEmpty, '일시중지를 눌렀는데 시트가 남음');
    await _expectValue(tester, '매칭 활성화', false, timeout: const Duration(seconds: 10));
    return null;
  }),
  'E-SET-70': _session((tester, job) async {
    await _openSettings(tester);
    await step('ready'); // PC 가 기기 토큰이 서버에 올라온 것을 확인한다
    await _settingsButton(tester, '탈퇴하기');
    await pumpUntil(tester, find.text('정말 떠나시나요?'), timeout: const Duration(seconds: 5));
    await tap(tester, button('영구 삭제'));
    await pumpUntil(tester, find.text('정말 삭제할까요?'), timeout: const Duration(seconds: 5));
    await tap(tester, button('정말 영구 삭제'));
    await arrive(tester, 'login', timeout: const Duration(seconds: 15));
    final at = await appears(tester, find.text(_withdrawnToast), const Duration(seconds: 10));
    must(at != null, '10초 안에 "$_withdrawnToast" 토스트가 안 나옴');
    await wait(tester, const Duration(seconds: 3, milliseconds: 500));
    must(find.text(_withdrawnToast).evaluate().isEmpty, '3초가 지났는데 토스트가 남음');
    return null;
  }),
};
