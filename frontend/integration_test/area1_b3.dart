part of 'area1.dart';

// 영역 1 묶음 3 — 사진 세트(04-2 사진 고르기 · 04-3 거절용 사진). 3b 학생증 제출 시나리오는 2026-10-17 학생증 제거로 뺐다.
// PC 쪽은 e2e/area1_b3.py 의 같은 번호 — 계정을 만들고 사진 파일을 앱 캐시(e2e-photos/)에 넣은 뒤 DB · 버킷을 본다.
// 갤러리는 뷰모델의 pickFromGallery 훅을 그 파일로 갈아끼운다(E-ONB-55 와 같은 방식).
// 아바타 작업 등록(avatar/generate, 유료)은 이 묶음에서 나가면 안 된다 — 04-3 까지 가는 건 E-ONB-23 하나이고 거기엔 막이를 건다.

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
