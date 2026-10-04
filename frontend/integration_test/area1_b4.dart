part of 'area1.dart';

// 영역 1 묶음 4 — 아바타(04-3 작업 등록 · 05-12 결과 화면 · 5회 실패 보상).
// PC 쪽은 e2e/area1_b4.py 의 같은 번호 — 계정과 아바타 행을 만들고, 앱이 끝난 뒤(또는 멈춘 사이) DB 를 본다.
// 실제 생성(운영 비용)은 E-ONB-24 · 41 뿐이다. E-ONB-25 는 아래에서 작업 등록을 막아 두고, 나머지는 05-12 에서 시작한다.

const _making = '아바타를 만들고 있어요';
const _couldNot = '아바타를 만들지 못했어요';
const _complete = '아바타가 완성됐어요';
const _fallbackTitle = '기본 아바타로 대신했어요';
const _fallbackBody = '서버 오류로 하트 10개 드렸어요';
const _retryLabel = '다시 만들기';
const _makeAvatarLabel = '이 사진으로 아바타 만들기';

/// 작업 등록까지 두 장 업로드(SafeSearch 포함)가 걸리는 시간을 넉넉히 본다 — 생성은 1분쯤 걸리니 그 전에 넘어가면 "기다리지 않는" 것이다.
const _registerWithin = Duration(seconds: 15);

/// FNV-1a 32비트 — e2e/area1_b4.py `_fnv` 와 같은 식이다. 압축을 거친 파일이라 원본 해시가 아니라 올라간 파일의 해시다.
String _fnv(File file) {
  var hash = 0x811c9dc5;
  for (final byte in file.readAsBytesSync()) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// 04-2 에서 [names] 를 고르고 "다음" → 04-3.
Future<void> _toAvatarSource(WidgetTester tester, List<String> names) async {
  await arrive(tester, '04-2');
  final state = await _pick(tester, names);
  _facesKept(state, names.length);
  await tap(tester, button('다음'));
  await arrive(tester, '04-3', timeout: const Duration(seconds: 10));
}

/// 04-3 "이 사진으로 아바타 만들기" → 04-4. 걸린 시간.
Future<Duration> _makeAvatar(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  await tap(tester, button(_makeAvatarLabel));
  await arrive(tester, '04-4', timeout: const Duration(seconds: 30));
  return watch.elapsed;
}

/// 05-12 에서 "만들지 못했어요" + "다시 만들기" 가 뜰 때까지.
Future<void> _failedScreen(WidgetTester tester) async {
  await arrive(tester, '05-12');
  await pumpUntil(tester, find.text(_couldNot), timeout: const Duration(seconds: 20));
}

AvatarGenerationViewModel _avatarViewModel(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(screen('05-12'))).read(avatarGenerationViewModelProvider.notifier);

/// 보상 시트 확인 → 완성 화면의 "다음" → 06-1. (코드: 시트는 "확인" 으로 닫히고, 06-1 로는 그 아래 "다음" 이 보낸다.)
Future<void> _confirmFallback(WidgetTester tester) async {
  must(find.textContaining(_fallbackBody).evaluate().isNotEmpty, '보상 안내에 "$_fallbackBody" 가 없음');
  await tap(tester, button('확인'));
  await pumpUntil(tester, find.text(_complete), timeout: const Duration(seconds: 5));
  await tap(tester, button('다음'));
  await arrive(tester, '06-1', timeout: const Duration(seconds: 10));
}

final Map<String, Area1Case> _b4Cases = {
  // 실제 생성 1 — 등록만 하고 기다리지 않는다. 행(profile_photos · profile_avatars)은 PC 가 본다.
  'E-ONB-24': _session((tester, job) async {
    await _toAvatarSource(tester, _photoNames(job));
    final took = await _makeAvatar(tester);
    must(took <= _registerWithin, '04-4 까지 ${took.inSeconds}초 — 생성을 기다린 듯함(${_registerWithin.inSeconds}초 안이어야 함)');
    return {'note': '04-4 까지 ${took.inMilliseconds}ms'};
  }),
  // 작업 등록을 막아 둔다(E-ONB-23 과 같은 막이: 만드는 중이면 generate() 가 아무것도 보내지 않는다) → 비용 0.
  // 끌어다 놓기는 뷰모델의 swapPhotos(from, to) 가 하는 일이다 — 제스처 대신 그 함수를 부른다.
  'E-ONB-25': _session((tester, job) async {
    await arrive(tester, '04-2');
    final container = ProviderScope.containerOf(tester.element(screen('04-2')));
    container.read(avatarGenerationViewModelProvider.notifier).state =
        const AvatarGenerationUiState(status: AvatarGenerationStatus.generating);
    final picked = await _pick(tester, _photoNames(job));
    _facesKept(picked, 3);
    List<String> order() => [for (final photo in container.read(photosViewModelProvider).photos) _fnv(photo.file!)];
    final before = order();
    container.read(photosViewModelProvider.notifier).swapPhotos(2, 0);
    await tester.pump(const Duration(milliseconds: 300));
    final after = order();
    must(after.length == 3 && after[0] == before[2] && after[2] == before[0], '3번째를 첫 칸으로 끌었는데 순서가 $before → $after');
    await tap(tester, button('다음'));
    await arrive(tester, '04-3', timeout: const Duration(seconds: 10));
    await _makeAvatar(tester);
    return {'before': before, 'hashes': after};
  }),
  // 만드는 중 행 → PC 가 완성으로 바꾼 뒤 10초 안에 완성 화면(상태 조회는 5초 간격: avatar_generation_view_model.dart _pollInterval).
  'E-ONB-34': _session((tester, job) async {
    await arrive(tester, '05-12');
    await pumpUntil(tester, find.text(_making), timeout: const Duration(seconds: 20));
    await step('ready');
    final took = await appears(tester, find.text(_complete), const Duration(seconds: 10));
    must(took != null, '완성 기록 뒤 10초 안에 "$_complete" 가 안 뜸');
    return {'note': '완성 기록 뒤 ${took!.inMilliseconds}ms'};
  }),
  // 11분 전에 만들기 시작한 행 — 서버가 failed 로 보여 준다.
  'E-ONB-35': _session((tester, job) async {
    await _failedScreen(tester);
    must(find.widgetWithText(AppButton, _retryLabel).evaluate().length == 1, '"$_retryLabel" 버튼이 1개가 아님');
    must(find.text(_making).evaluate().isEmpty, '실패 화면에 "$_making" 가 같이 보임');
    return null;
  }),
  // 아바타 행이 없던 사람 — 실패 화면에서 다시 만들기 → 만드는 중.
  'E-ONB-36': _session((tester, job) async {
    await _failedScreen(tester);
    await tap(tester, button(_retryLabel));
    await pumpUntil(tester, find.text(_making), timeout: const Duration(seconds: 10));
    return null;
  }),
  // 실패 5행 → 누르는 순간 서버가 기본 아바타 + 10하트.
  'E-ONB-37': _session((tester, job) async {
    await _failedScreen(tester);
    await tap(tester, button(_retryLabel));
    await pumpUntil(tester, find.text(_fallbackTitle), timeout: const Duration(seconds: 20));
    await _confirmFallback(tester);
    return null;
  }),
  // 실패 4행 + 깨진 원본 → 워커의 5번째 실패가 기본 아바타 + 10하트를 한 번만 준다(1~2분).
  'E-ONB-38': _session((tester, job) async {
    await _failedScreen(tester);
    await tap(tester, button(_retryLabel));
    await pumpUntil(tester, find.text(_fallbackTitle), timeout: const Duration(minutes: 3));
    await _confirmFallback(tester);
    return null;
  }),
  // 실패 4행 — 누른 바로 뒤에 PC 가 DB 를 본다. "다시 만들기" 버튼이 부르는 retry() 를 직접 불러 서버 응답까지 기다린 뒤 멈춘다
  // (버튼 누름은 응답을 기다릴 수 없어 PC 가 너무 일찍 볼 수 있다).
  'E-ONB-39': _session((tester, job) async {
    await _failedScreen(tester);
    must(find.widgetWithText(AppButton, _retryLabel).evaluate().isNotEmpty, '"$_retryLabel" 버튼이 없음');
    await _avatarViewModel(tester).retry();
    await tester.pump(const Duration(milliseconds: 300));
    must(find.text(_making).evaluate().isNotEmpty, '다시 만들기 뒤 "$_making" 가 아님');
    await step('registered');
    return null;
  }),
  // 첫 켬: 작업 등록 뒤 04-4 에서 끝(PC 가 설문까지 API 로 하고 완성을 기다린다). 다시 켬: 완성 행이 있어 서버 다음 단계가 06-1 —
  // 05-12 를 건너뛰고 06-1 로 바로 간다(onboarding_progress.py 'avatar' = avatar_ready).
  'E-ONB-41': _session((tester, job) async {
    if (!_fresh(job)) return _arriveAt(tester, job);
    await _toAvatarSource(tester, _photoNames(job));
    final took = await _makeAvatar(tester);
    return {'note': '04-4 까지 ${took.inMilliseconds}ms'};
  }),
};
