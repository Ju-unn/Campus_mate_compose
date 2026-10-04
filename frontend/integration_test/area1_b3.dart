part of 'area1.dart';

// 영역 1 묶음 3 — 사진 세트(3b 학생증 제출 · 04-2 사진 고르기 · 04-3 거절용 사진).
// PC 쪽은 e2e/area1_b3.py 의 같은 번호 — 계정을 만들고 사진 파일을 앱 캐시(e2e-photos/)에 넣은 뒤 DB · 버킷을 본다.
// 갤러리는 뷰모델의 pickFromGallery 훅을 그 파일로 갈아끼운다(E-ONB-55 와 같은 방식).
// 아바타 작업 등록(avatar/generate, 유료)은 이 묶음에서 나가면 안 된다 — 04-3 까지 가는 건 E-ONB-23 하나이고 거기엔 막이를 건다.

const _noFace = '얼굴이 보이는 사진으로 다시 올려주세요'; // NoFaceDetectedFailure
const _unreadable = '사진을 읽을 수 없어요. 다른 사진으로 다시 올려주세요'; // PhotoUnreadableFailure(졸업증명서만)
const _held = '조금 더 확인이 필요해요'; // 3b 대기 화면(status=pending) 제목
const _rejectReason = '사진이 흐려요'; // e2e/area1_b3.py REJECT_REASON — PC 가 반려하며 적는 사유
const _maxPhotosNotice = '사진은 최대 4장까지 올릴 수 있어요';
const _noneKept = '얼굴이 보이는 사진을 골라 주세요';
const _oneDropped = '1장은 얼굴이 보이지 않아 빠졌어요';
const _notSafe = '부적절한 사진은 올릴 수 없어요'; // 서버 errors.PHOTO_NOT_SAFE(422)

/// PC 가 앱 캐시에 넣어 둔 사진 세트 파일.
Future<File> _photo(String name) async {
  final file = File('${(await getTemporaryDirectory()).path}/e2e-photos/$name');
  if (!file.existsSync()) throw E2eBlocked('사진 세트 파일 없음: $name');
  return file;
}

List<String> _photoNames(Map<String, dynamic> job) => (job['photos'] as List).cast<String>();

// ── 3b 학생증 ───────────────────────────────────────────────────────────────────────────────────

/// 3b 제출 폼. 처음엔 히어로, 반려 뒤엔 배너가 제목 자리에 오므로 둘 다에 있는 제출 버튼으로 찾는다.
Finder get _proofForm => button(_submitProof);

/// 3b 의 입력칸은 실명 하나뿐이다(힌트는 고른 탭마다 다르다).
Finder get _realNameField => find.descendant(of: find.byType(TextFormField), matching: find.byType(TextField));

/// 폼에 일감의 탭 · 사진 · 실명을 넣고 버튼이 켜졌는지 본다(누르지는 않는다).
Future<ProviderContainer> _fillProof(WidgetTester tester, Map<String, dynamic> job) async {
  await pumpUntil(tester, _proofForm);
  final file = await _photo(job['photo'] as String);
  if (job['tab'] case final String tab) await tap(tester, find.text(tab));
  final container = ProviderScope.containerOf(tester.element(_proofForm));
  container.read(studentVerificationViewModelProvider.notifier).pickFromGallery = () async => file;
  await tap(tester, find.text('사진을 첨부해주세요'));
  await type(tester, _realNameField, job['real_name'] as String);
  must(enabled(tester, _submitProof), '사진 · 실명을 넣었는데 "$_submitProof" 가 꺼짐');
  return container;
}

/// 채워서 제출 → ('3c' | 'held' | 폼에 뜬 문구, 누른 뒤 걸린 시간).
Future<(String, Duration)> _sendProof(WidgetTester tester, Map<String, dynamic> job,
    {Duration within = const Duration(seconds: 40)}) async {
  final container = await _fillProof(tester, job);
  final watch = Stopwatch()..start();
  await tap(tester, _proofForm);
  while (watch.elapsed < within) {
    if (screen('3c').evaluate().isNotEmpty) return ('3c', watch.elapsed);
    if (find.text(_held).evaluate().isNotEmpty) return ('held', watch.elapsed);
    // submit 은 누르는 순간 isSubmitting 을 세우고 지난 문구를 지운다 — 여기 걸리면 이번 제출의 문구다.
    final state = container.read(studentVerificationViewModelProvider);
    if (!state.isSubmitting && state.errorMessage != null) return (state.errorMessage!, watch.elapsed);
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure('제출 뒤 ${within.inSeconds}초 안에 결과가 안 나옴');
}

/// 학생증 탭(얼굴 검사함)의 사진이 얼굴 검사에서 막혔으면 사진 세트 탓이다 — 판정하지 않는다.
void _faceFound(String outcome, Map<String, dynamic> job) {
  if (outcome == _noFace) throw E2eBlocked('${job['photo']} 에서 기기가 얼굴을 못 찾음 — 사진 세트 확인');
}

/// E-GATE-37 · 38 — 사람 검토로 넘어가 대기 화면, 제출 폼은 안 보인다.
Future<Map<String, Object?>?> _toReview(WidgetTester tester, Map<String, dynamic> job) async {
  final (outcome, _) = await _sendProof(tester, job);
  _faceFound(outcome, job);
  must(outcome == 'held', '"$_held" 화면이 아님: $outcome');
  must(_realNameField.evaluate().isEmpty, '대기 화면에 실명 칸이 남음');
  return null;
}

/// 제출 → 대기 화면 → step('pending') 에서 PC 가 반려 → 폼이 배너와 함께 돌아오기까지(step 이 끝난 때부터 잼).
///
/// 35초 근거(코드): 대기 화면은 status=pending 이 그려지는 build 에서 30초 주기 타이머를 건다
/// (student_verification_screen.dart:19 `_pollInterval` · :81-88 `_syncPolling`). 첫 조회는 대기 화면이 뜬 지 30초 뒤이고,
/// step 왕복(PC 의 반려 PATCH 2번)만큼 이미 지났으므로 step 뒤로는 30초 안쪽 + 상태 조회 한 번이다.
/// 조회가 rejected 를 받으면 VM 이 사유를 실어(_stateFromOutcome) 폼 + 배너가 된다.
/// 더 빠른 길: profiles 를 바꾸면 DB 트리거 → /hooks/verification-reviewed → FCM(route=verification) →
/// main.dart `_refreshForRoute` 가 refreshStatus 를 부른다. 조용한 시간엔 서버가 알림을 버리므로 폴링만 믿는다.
/// PC 의 반려가 30초를 넘기면 첫 조회가 pending 을 받아 다음 조회(60초)로 밀린다 — 그때는 35초를 못 맞춘다.
Future<Duration> _heldThenRejected(WidgetTester tester, Map<String, dynamic> job) async {
  final (outcome, _) = await _sendProof(tester, job);
  _faceFound(outcome, job);
  must(outcome == 'held', '"$_held" 화면이 아님: $outcome');
  await step('pending');
  final back = await appears(tester, find.textContaining(_rejectReason), const Duration(seconds: 35));
  must(back != null, '반려 뒤 35초 안에 배너 "$_rejectReason" 가 안 나옴');
  must(_proofForm.evaluate().isNotEmpty, '배너는 떴는데 제출 폼이 없음');
  return back!;
}

// ── 04-2 사진 고르기 ────────────────────────────────────────────────────────────────────────────

/// 04-2 의 갤러리가 [names] 를 돌려주게 하고 "사진 추가" 를 누른다 → 얼굴 검사까지 끝난 상태.
/// 갤러리가 받은 장수 제한(남은 칸)은 [asked] 에 담는다. 제한과 상관없이 다 돌려주는 건 뷰모델의 take(room) 을 보려는 것이다
/// (진짜 갤러리 pickMultiImage(limit) 도 막지만, 막지 않는 기기에서도 4장을 넘지 않아야 한다).
Future<PhotosUiState> _pick(WidgetTester tester, List<String> names, {List<int>? asked}) async {
  final files = [for (final name in names) await _photo(name)];
  final container = ProviderScope.containerOf(tester.element(screen('04-2')));
  container.read(photosViewModelProvider.notifier).pickFromGallery = (limit) async {
    asked?.add(limit);
    return files;
  };
  await tap(tester, find.text('사진 추가').first);
  final watch = Stopwatch()..start();
  while (container.read(photosViewModelProvider).isCheckingPhotos) {
    must(watch.elapsed < const Duration(seconds: 20), '20초 안에 얼굴 검사가 안 끝남');
    await tester.pump(const Duration(milliseconds: 200));
  }
  return container.read(photosViewModelProvider);
}

/// 얼굴 사진이 [count] 장보다 적게 남았으면 사진 세트 탓이다 — 판정하지 않는다.
void _facesKept(PhotosUiState state, int count) {
  if (state.photos.length < count) {
    throw E2eBlocked('얼굴 사진이 기기 얼굴 검사에서 빠짐(${state.photos.length}/$count장, ${state.errorMessage}) — 사진 세트 확인');
  }
}

/// [message] 가 뷰모델 상태와 토스트(3초) 둘 다에 있어야 한다.
void _notice(WidgetTester tester, PhotosUiState state, String message) {
  must(state.errorMessage == message, '문구가 "$message" 가 아님: ${state.errorMessage}');
  must(find.text(message).evaluate().isNotEmpty, '"$message" 토스트가 화면에 없음');
}

final Map<String, Area1Case> _b3Cases = {
  // 얼굴 검사에서 막혀 서버를 안 부른다(attempts 0행 · 버킷 0개는 PC 가 본다).
  'E-GATE-34': _session((tester, job) async {
    final (outcome, _) = await _sendProof(tester, job);
    must(outcome == _noFace, '얼굴 없는 사진인데 결과가 "$outcome"');
    must(find.text(_noFace).evaluate().isNotEmpty, '"$_noFace" 가 화면에 없음');
    return null;
  }),
  // 졸업증명서 탭은 requiresFace=false(student_verification_screen.dart:181,217) → VM 이 압축만 하고 얼굴 검사를 건너뛴다
  // (student_verification_view_model.dart:137-139). 압축이 던지면 null → "사진을 읽을 수 없어요"(:152) — 그것도 fail.
  'E-GATE-35': _session((tester, job) async {
    final (outcome, _) = await _sendProof(tester, job);
    must(outcome != _noFace, '졸업증명서인데 얼굴 검사에 막힘');
    must(outcome != _unreadable, '기기가 사진을 못 읽음: $outcome');
    must(outcome == '3c' || outcome == 'held', '서버 결과 화면(3c · 대기)이 아님: $outcome');
    return {'note': outcome == '3c' ? '통과 → 3c' : '사람 검토 대기'};
  }),
  'E-GATE-36': _session((tester, job) async {
    final (outcome, took) = await _sendProof(tester, job, within: const Duration(seconds: 10));
    _faceFound(outcome, job);
    must(outcome == '3c', '제출 결과가 3c 가 아님: $outcome');
    return {'note': '3c 까지 ${took.inMilliseconds}ms'};
  }),
  'E-GATE-37': _session(_toReview),
  // 학교 다른 학생증 · 글자 없는 사진 — PC 가 계정 · 사진을 바꿔 앱을 두 번 켠다.
  'E-GATE-38': _session(_toReview),
  'E-GATE-44': _session((tester, job) async {
    final back = await _heldThenRejected(tester, job);
    // 돌아온 폼은 입력을 비운다(VM _stateFromOutcome) — 버튼은 사진 · 실명을 다시 넣어야 켜진다.
    // 다시 넣어 켜지는지까지 보고 누르지는 않는다(PC 가 마지막 행이 rejected 인지 본다).
    final offAtFirst = !enabled(tester, _submitProof);
    await _fillProof(tester, job);
    return {'note': '반려 뒤 폼까지 ${back.inMilliseconds}ms · 돌아온 직후 버튼 ${offAtFirst ? '꺼짐(입력 비움)' : '켜짐'} → 다시 넣어 켜짐'};
  }),
  // 한 번 켤 때 제출 1번 — PC 가 같은 계정으로 앱을 3번 켜며 turn 을 올린다.
  'E-GATE-45': _session((tester, job) async {
    final back = await _heldThenRejected(tester, job);
    return {'note': '${(job['turn'] as int? ?? 0) + 1}번째 · 반려 뒤 폼까지 ${back.inMilliseconds}ms'};
  }),
  'E-ONB-20': _session((tester, job) async {
    await arrive(tester, '04-2');
    final names = _photoNames(job);
    for (final (count, on) in [(1, false), (2, true)]) {
      final state = await _pick(tester, [names[count - 1]]);
      _facesKept(state, count);
      must(enabled(tester, '다음') == on, '$count장에 다음이 ${on ? '꺼짐' : '켜짐'}');
    }
    return null;
  }),
  'E-ONB-21': _session((tester, job) async {
    await arrive(tester, '04-2');
    final asked = <int>[];
    final state = await _pick(tester, _photoNames(job), asked: asked);
    must(asked.length == 1 && asked.single == 4, '갤러리에 물은 장수 $asked(남은 칸 4 여야 함)');
    _facesKept(state, 4);
    must(state.photos.length == 4, '5장을 넣었는데 ${state.photos.length}장');
    must(find.text('사진 추가').evaluate().isEmpty, '4장인데 "사진 추가" 칸이 남음');
    // 4장이면 빈 칸이 없어(photo_tiles.dart PhotoSlotGrid._slot) 화면으로는 더 누를 곳이 없다 — 그 칸이 부르는 addPhoto 를 직접 부른다.
    final container = ProviderScope.containerOf(tester.element(screen('04-2')));
    await container.read(photosViewModelProvider.notifier).addPhoto();
    await tester.pump(const Duration(milliseconds: 300));
    final after = container.read(photosViewModelProvider);
    _notice(tester, after, _maxPhotosNotice);
    must(after.photos.length == 4, '더 넣으려 한 뒤 ${after.photos.length}장');
    return {'note': '4장 뒤 "사진 추가" 칸 없음 — 문구는 addPhoto 직접 호출로 확인'};
  }),
  // 일감은 얼굴 2 + 풍경 1(풍경이 끝). 풍경만 고르기를 빈 04-2 에서 먼저 해야 "0장" 이 된다.
  'E-ONB-22': _session((tester, job) async {
    await arrive(tester, '04-2');
    final names = _photoNames(job);
    final alone = await _pick(tester, [names.last]);
    must(alone.photos.isEmpty, '풍경 한 장이 칸에 들어감');
    _notice(tester, alone, _noneKept);
    final mixed = await _pick(tester, names);
    _facesKept(mixed, 2);
    must(mixed.photos.length == 2, '얼굴 2 + 풍경 1 중 ${mixed.photos.length}장이 들어감');
    _notice(tester, mixed, _oneDropped);
    return null;
  }),
  // 04-3 "이 사진으로 아바타 만들기" 는 사진을 자리 0 · 1 순서로 올리고 모두 받아져야 아바타 작업을 등록한다
  // (photos_view_model.dart submit → _submittedState → _withAvatarRequested). 거절용(자리 1)이 422 면 등록 전에 멈춘다.
  'E-ONB-23': _session((tester, job) async {
    await arrive(tester, '04-2');
    final container = ProviderScope.containerOf(tester.element(screen('04-2')));
    // 비용 막이: generate() 는 만드는 중이면 아무것도 보내지 않고 null 을 준다(avatar_generation_view_model.dart:43-46).
    // 거절용이 SafeSearch 를 통과해 버려도 유료 작업이 등록되지 않는다 — 그때 이 가설은 아래 문구 확인에서 fail 이다.
    container.read(avatarGenerationViewModelProvider.notifier).state =
        const AvatarGenerationUiState(status: AvatarGenerationStatus.generating);
    final state = await _pick(tester, _photoNames(job));
    _facesKept(state, 2); // 거절용에 얼굴이 없으면 기기에서 먼저 빠진다(시나리오 E-ONB-23 준비 칸)
    await tap(tester, button('다음'));
    await arrive(tester, '04-3', timeout: const Duration(seconds: 10));
    // 원본은 04-2 → 04-3 에서 첫 장(얼굴 사진)으로 골라져 있다(prepareAvatarSource).
    await tap(tester, button('이 사진으로 아바타 만들기'));
    await pumpUntil(tester, find.text(_notSafe), timeout: const Duration(seconds: 30));
    await wait(tester, const Duration(seconds: 2));
    must(screen('04-3').evaluate().isNotEmpty, '거절 뒤 04-3 을 벗어남');
    return null;
  }),
};
