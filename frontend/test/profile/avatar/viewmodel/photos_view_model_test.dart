import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/media/model/repository/face_detector_provider.dart';
import 'package:campus_mate/auth/media/model/repository/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/profile/avatar/model/repository/avatar_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';
import 'package:campus_mate/profile/avatar/model/repository/photos_repository_provider.dart';
import 'package:campus_mate/profile/avatar/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/avatar/viewmodel/photos_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/draft/shared_preferences_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../auth/media/model/repository/fake_face_detector.dart';
import '../../../auth/media/model/repository/fake_image_compressor.dart';
import '../../../core/analytics/fake_analytics_service.dart';
import '../model/repository/fake_avatar_repository.dart';
import '../../onboarding/model/repository/fake_onboarding_repository.dart';
import '../model/repository/fake_photos_repository.dart';
import '../../../core/draft/fake_draft_store.dart';

void main() {
  late FakePhotosRepository repository;
  late FakeImageCompressor imageCompressor;
  late FakeFaceDetector faceDetector;
  late FakeOnboardingRepository onboardingRepository;
  late FakeAvatarRepository avatarRepository;
  late FakeAnalyticsService analytics;
  late ProviderContainer container;

  setUp(() {
    repository = FakePhotosRepository();
    imageCompressor = FakeImageCompressor();
    faceDetector = FakeFaceDetector();
    onboardingRepository = FakeOnboardingRepository();
    avatarRepository = FakeAvatarRepository();
    analytics = FakeAnalyticsService();
    container = ProviderContainer(
      overrides: [
        analyticsServiceProvider.overrideWithValue(analytics),
        photosRepositoryProvider.overrideWithValue(repository),
        imageCompressorProvider.overrideWithValue(imageCompressor),
        faceDetectorProvider.overrideWithValue(faceDetector),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
        // 04-3 "다음"이 사진 업로드에 이어 아바타 작업까지 등록한다.
        avatarRepositoryProvider.overrideWithValue(avatarRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  PhotosViewModel buildViewModel(List<File> photosToPick) {
    final viewModel = container.read(photosViewModelProvider.notifier);
    var index = 0;
    viewModel.pickFromGallery = (limit) async => [photosToPick[index++]];
    return viewModel;
  }

  test('얼굴이 보이지 않는 사진은 칸에 넣지 않고 안내를 남긴다', () async {
    final viewModel = buildViewModel([File('a.jpg')]);
    faceDetector.nextResult = false;

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect(state.photos, isEmpty);
    expect(state.error, _noFace);
  });

  test('여러 장을 한 번에 고르면 얼굴이 있는 것만 들어간다', () async {
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [File('a.jpg'), File('b.jpg'), File('c.jpg')];
    // 가운데 두 장에 얼굴이 없다.
    faceDetector.queuedResults.addAll([true, false, false]);

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect([for (final photo in state.photos) photo.file!.path], ['a.jpg']);
    expect(state.error, _rejectedCount(2));
  });

  test('일부만 빠지면 몇 장이 빠졌는지 알린다', () async {
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [File('a.jpg'), File('b.jpg')];
    faceDetector.queuedResults.addAll([true, false]);

    await viewModel.addPhoto();

    expect(container.read(photosViewModelProvider).error, _rejectedCount(1));
  });

  test('한 장도 못 들어가면 장수 대신 다시 고르라고 알린다', () async {
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [File('a.jpg'), File('b.jpg')];
    faceDetector.nextResult = false;

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect(state.photos, isEmpty);
    expect(state.error, _noFace);
  });

  test('압축에 실패한 사진도 빠진 장으로 세고 기다리는 표시를 내린다', () async {
    // 압축이 try 밖에 있으면 예외가 새어 나가 기다리는 표시가 굳는다.
    final viewModel = buildViewModel([File('a.jpg')]);
    imageCompressor.nextError = Exception('사진을 읽지 못했다');

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect(state.photos, isEmpty);
    expect(state.isCheckingPhotos, isFalse);
    expect(state.error, _noFace);
  });

  test('갤러리가 예외를 던져도 기다리는 표시가 굳지 않는다', () async {
    // 권한 거부 등 PlatformException — 고르지 않고 닫은 것과 같이 다룬다.
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => throw Exception('권한 거부');

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect(state.photos, isEmpty);
    expect(state.isCheckingPhotos, isFalse);
  });

  test('살펴보는 중에 다시 눌러도 남은 칸을 두 번 세지 않는다', () async {
    // 두 번 세면 5~6장이 담겨 "다음"이 영영 켜지지 않는다.
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [for (var i = 0; i < limit; i++) File('p$i.jpg')];
    final gate = Completer<bool>();
    faceDetector.gate = gate;

    final first = viewModel.addPhoto();
    await pumpEventQueue();
    final second = viewModel.addPhoto();
    gate.complete(true);
    await Future.wait([first, second]);

    expect(container.read(photosViewModelProvider).photos, hasLength(4));
  });

  test('남은 칸 수만큼만 고르게 하고, 더 돌려줘도 남은 칸까지만 담는다', () async {
    final viewModel = buildViewModel([File('a.jpg')]);
    await viewModel.addPhoto();
    final limits = <int>[];
    viewModel.pickFromGallery = (limit) async {
      limits.add(limit);
      return [for (var i = 0; i < 5; i++) File('p$i.jpg')];
    };

    await viewModel.addPhoto();

    expect(limits, [3]);
    expect(container.read(photosViewModelProvider).photos, hasLength(4));
  });

  test('copyWith 는 넘기지 않은 표시를 그대로 이어받는다', () {
    // 검사가 늦게 끝난 addPhoto 가 isSubmitting 을 지우면 같은 사진을 두 번 올릴 수 있다.
    const state = PhotosUiState(isSubmitting: true, error: UnknownFailure());

    final next = state.copyWith(photos: [SelectedPhoto(File('a.jpg'))]);

    expect(next.isSubmitting, isTrue);
    expect(next.error, isA<UnknownFailure>());
    expect(next.copyWith(error: null).error, isNull);
  });

  test('검출기가 예외를 던지면 막지 않고 통과시킨다', () async {
    // 기기 검사는 1차 필터일 뿐이라, 검출기 장애로 사진을 못 고르게 막는 쪽이 더 나쁘다.
    final viewModel = buildViewModel([File('a.jpg')]);
    faceDetector.nextError = Exception('ML Kit 이 사진을 읽지 못했다');

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect(state.photos.length, 1);
    expect(state.error, isNull);
  });

  test('살펴보는 동안 isCheckingPhotos 가 켜진다', () async {
    final viewModel = container.read(photosViewModelProvider.notifier);
    final gate = Completer<bool>();
    faceDetector.gate = gate;
    viewModel.pickFromGallery = (limit) async => [File('a.jpg')];

    final adding = viewModel.addPhoto();
    await pumpEventQueue();
    expect(container.read(photosViewModelProvider).isCheckingPhotos, isTrue);

    gate.complete(true);
    await adding;

    expect(container.read(photosViewModelProvider).isCheckingPhotos, isFalse);
    expect(container.read(photosViewModelProvider).photos.length, 1);
  });

  test('사진이 2장 미만이면 제출할 수 없다', () async {
    final viewModel = buildViewModel([File('a.jpg')]);
    await viewModel.addPhoto();
    expect(container.read(photosViewModelProvider).canSubmit, isFalse);
  });

  test('자리를 바꿔도 아바타 원본 표시는 그 사진을 따라간다', () async {
    // 표시가 자리에 남으면 04-3 에서 고른 사진과 다른 사진이 아바타 원본으로 올라간다.
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    viewModel.setAvatarSource(1);

    viewModel.swapPhotos(1, 0);

    final photos = container.read(photosViewModelProvider).photos;
    expect(photos[0].file!.path, 'b.jpg');
    expect(photos[0].isAvatarSource, isTrue);
    expect(photos[1].isAvatarSource, isFalse);
  });

  test('없는 칸과는 자리를 바꾸지 않는다', () async {
    // 빈 칸으로 끌어다 놓은 경우다 — 순서에 구멍이 나면 올릴 때 position 이 어긋난다.
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();

    viewModel.swapPhotos(0, 3);

    final photos = container.read(photosViewModelProvider).photos;
    expect([for (final photo in photos) photo.file!.path], ['a.jpg', 'b.jpg']);
  });

  test('아바타 원본을 정확히 1장 고르지 않으면 제출할 수 없다', () async {
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    expect(container.read(photosViewModelProvider).canSubmit, isFalse);
  });

  test('2장이면 04-3 으로 넘어갈 수 있고, 넘어갈 때 원본이 없으면 첫 장을 골라 둔다', () async {
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    expect(container.read(photosViewModelProvider).canProceed, isTrue);

    viewModel.prepareAvatarSource();

    final photos = container.read(photosViewModelProvider).photos;
    expect(photos.map((p) => p.isAvatarSource), [true, false]);
    expect(container.read(photosViewModelProvider).canSubmit, isTrue);
  });

  test('이미 고른 원본은 04-3 으로 다시 넘어가도 바뀌지 않는다', () async {
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    viewModel.setAvatarSource(1);

    viewModel.prepareAvatarSource();

    expect(container.read(photosViewModelProvider).photos.map((p) => p.isAvatarSource), [false, true]);
  });

  test('최대 4장까지만 담긴다', () async {
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg'), File('c.jpg'), File('d.jpg'), File('e.jpg')]);
    for (var i = 0; i < 5; i++) {
      await viewModel.addPhoto();
    }
    expect(container.read(photosViewModelProvider).photos, hasLength(4));
  });

  test('4장이 다 차면 말없이 무시하지 않고 안내 문구를 남긴다', () async {
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg'), File('c.jpg'), File('d.jpg'), File('e.jpg')]);
    for (var i = 0; i < 5; i++) {
      await viewModel.addPhoto();
    }

    expect(container.read(photosViewModelProvider).error, isA<PhotoMaxFailure>().having((failure) => failure.max, 'max', 4));
  });

  group('같은 사진(원본 바이트가 같은 사진)은 한 번만 담는다', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('photos_duplicate_test'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    /// 갤러리는 같은 사진도 고를 때마다 다른 경로로 준다 — 경로가 아니라 내용으로 가려야 한다.
    File photo(String name, String content) => File('${tempDir.path}/$name')..writeAsStringSync(content);

    List<String> pickedPaths() => [for (final p in container.read(photosViewModelProvider).photos) p.file!.path];

    test('sha256OfFile — 바이트가 같으면 같은 값, 다르면 다른 값, 읽지 못하면 null', () {
      final a = sha256OfFile(photo('a.jpg', 'same').path);
      expect(a, sha256OfFile(photo('a-again.jpg', 'same').path));
      expect(a, isNot(sha256OfFile(photo('b.jpg', 'other').path)));
      expect(a, hasLength(64));
      expect(sha256OfFile('${tempDir.path}/missing.jpg'), isNull);
    });

    test('같은 사진을 두 번 고르면 한 장만 담고 같은 사진 안내를 남긴다', () async {
      final first = photo('a.jpg', 'same');
      final viewModel = buildViewModel([first, photo('a-again.jpg', 'same')]);

      await viewModel.addPhoto();
      await viewModel.addPhoto();

      expect(pickedPaths(), [first.path]);
      expect(container.read(photosViewModelProvider).error, isA<PhotoDuplicateFailure>());
    });

    test('한 번에 고른 묶음 안에서 겹치면 겹친 것만 빼고 안내는 한 번이다', () async {
      final a = photo('a.jpg', 'same');
      final b = photo('b.jpg', 'other');
      final viewModel = container.read(photosViewModelProvider.notifier)
        ..pickFromGallery = (limit) async => [a, photo('a-again.jpg', 'same'), b];

      await viewModel.addPhoto();

      expect(pickedPaths(), [a.path, b.path]);
      expect(container.read(photosViewModelProvider).error, isA<PhotoDuplicateFailure>());
    });

    test('내용이 다른 사진은 막지 않는다', () async {
      final a = photo('a.jpg', 'one');
      final b = photo('b.jpg', 'two');
      final viewModel = buildViewModel([a, b]);

      await viewModel.addPhoto();
      await viewModel.addPhoto();

      expect(pickedPaths(), [a.path, b.path]);
      expect(container.read(photosViewModelProvider).error, isNull);
    });

    test('뺀 사진은 다시 고를 수 있다', () async {
      final a = photo('a.jpg', 'same');
      final again = photo('a-again.jpg', 'same');
      final viewModel = buildViewModel([a, again]);

      await viewModel.addPhoto();
      viewModel.removePhoto(0);
      await viewModel.addPhoto();

      expect(pickedPaths(), [again.path]);
      expect(container.read(photosViewModelProvider).error, isNull);
    });

    test('같은 사진이 막혀도 얼굴 없는 사진으로 세지 않는다 — 가입 막힘을 남기지 않는다', () async {
      final viewModel = buildViewModel([photo('a.jpg', 'same'), photo('a-again.jpg', 'same')]);

      await viewModel.addPhoto();
      await viewModel.addPhoto();

      expect(analytics.calls.where((call) => call.startsWith('onboarding_blocked')), isEmpty);
    });
  });

  test('2장 이상 + 아바타 원본 1장이면 제출할 수 있고 성공하면 completed 가 켜진다', () async {
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    viewModel.setAvatarSource(0);

    await viewModel.submit();

    final state = container.read(photosViewModelProvider);
    expect(state.completed, isTrue);
    expect(repository.uploads, hasLength(2));
    expect(repository.uploads[0].isAvatarSource, isTrue);
    expect(repository.uploads[1].isAvatarSource, isFalse);
    expect(onboardingRepository.fetchCount, 1);
  });

  test('사진을 다 올리면 이어서 아바타 작업까지 등록한다', () async {
    // 등록이 먼저, 이동이 나중이다 — 순서가 뒤집히면 넘어간 뒤에 등록이 실패해도 보여 줄 자리가 없다.
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    viewModel.setAvatarSource(0);

    await viewModel.submit();

    expect(avatarRepository.generateCount, 1);
    expect(container.read(photosViewModelProvider).completed, isTrue);
  });

  test('아바타 등록이 막히면 04-3 에 머문다', () async {
    // 원본 사진이 없다 같은, 사람이 고칠 수 있는 오류다. completed 를 세우면 그대로 넘어가 버린다.
    avatarRepository.nextResult = const FailureResult(ServerRejectedFailure('아바타 원본 사진을 먼저 골라 주세요'));
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    viewModel.setAvatarSource(0);

    await viewModel.submit();

    final state = container.read(photosViewModelProvider);
    expect(state.completed, isFalse);
    expect(state.error, _rejected('아바타 원본 사진을 먼저 골라 주세요'));
    expect(onboardingRepository.fetchCount, 0);
  });

  test('작업을 등록하는 동안에도 기다리는 표시가 내려가지 않는다', () async {
    // 업로드가 끝나자마자 state 를 갈아 끼우면 isSubmitting 이 내려가 토스트가 꺼진다 —
    // 등록하는 동안 화면에 아무 표시도 없게 된다.
    avatarRepository.generateGate = Completer<void>();
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    viewModel.setAvatarSource(0);

    final submitting = viewModel.submit();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(photosViewModelProvider).isSubmitting, isTrue);
    expect(avatarRepository.generateCount, 1);

    avatarRepository.generateGate!.complete();
    await submitting;

    expect(container.read(photosViewModelProvider).isSubmitting, isFalse);
  });

  test('업로드가 실패하면 completed 가 켜지지 않는다', () async {
    repository.nextResult = const FailureResult(NetworkFailure());
    final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
    await viewModel.addPhoto();
    await viewModel.addPhoto();
    viewModel.setAvatarSource(0);

    await viewModel.submit();

    expect(container.read(photosViewModelProvider).completed, isFalse);
    expect(container.read(photosViewModelProvider).error, isNotNull);
  });

  group('서버가 글자 많은 사진을 거절(422 `photo_looks_like_document`)', () {
    const document = FailureResult<void>(ServerRejectedFailure('서버 임시 문구', code: photoLooksLikeDocumentCode));

    Future<PhotosViewModel> threePhotos() async {
      final viewModel = buildViewModel([File('a.jpg'), File('b.jpg'), File('c.jpg')]);
      for (var i = 0; i < 3; i++) {
        await viewModel.addPhoto();
      }
      viewModel.setAvatarSource(0);
      return viewModel;
    }

    List<String> paths() => [for (final photo in container.read(photosViewModelProvider).photos) photo.file!.path];

    test('거절된 그 사진만 칸에서 빼고 문서 사진 표시를 켠다 — 서버 문구는 쓰지 않고 아바타 작업도 등록하지 않는다', () async {
      final viewModel = await threePhotos();
      repository.resultAt[1] = document;

      await viewModel.submit();

      final state = container.read(photosViewModelProvider);
      expect(state.documentRejected, isTrue);
      expect(state.error, isNull);
      expect(paths(), ['a.jpg', 'c.jpg']);
      expect((state.isSubmitting, state.completed), (false, false));
      expect(avatarRepository.generateCount, 0);
    });

    for (final (name, clear) in <(String, Future<void> Function(PhotosViewModel))>[
      ('사진을 빼면', (viewModel) async => viewModel.removePhoto(0)),
      ('새로 고르면', (viewModel) async {
        viewModel.pickFromGallery = (limit) async => [File('d.jpg')];
        await viewModel.addPhoto();
      }),
      ('다시 올리면', (viewModel) async {
        repository.resultAt.clear();
        viewModel.setAvatarSource(0);
        await viewModel.submit();
      }),
    ]) {
      test('$name 표시가 꺼진다', () async {
        final viewModel = await threePhotos();
        repository.resultAt[1] = document;
        await viewModel.submit();
        expect(container.read(photosViewModelProvider).documentRejected, isTrue);

        await clear(viewModel);

        expect(container.read(photosViewModelProvider).documentRejected, isFalse);
      });
    }

    test('올리는 동안 목록이 바뀌어도 거절된 그 사진만 뺀다 — 자리 번호가 아니라 사진으로 찾는다', () async {
      final viewModel = await threePhotos();
      repository
        ..holdAt[1] = Completer<void>()
        ..resultAt[1] = document;

      final submitting = viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      viewModel.removePhoto(0); // 올리는 중에 앞 사진이 빠진다 → [b, c]
      repository.holdAt[1]!.complete();
      await submitting;

      expect(paths(), ['c.jpg'], reason: '거절된 b 만 빠지고 c 는 남는다');
      expect(container.read(photosViewModelProvider).documentRejected, isTrue);
    });

    test('올리는 동안 목록이 짧아져도 RangeError 없이 거절된 사진만 뺀다', () async {
      final viewModel = await threePhotos();
      repository
        ..holdAt[2] = Completer<void>()
        ..resultAt[2] = document;

      final submitting = viewModel.submit();
      await Future<void>.delayed(Duration.zero);
      viewModel
        ..removePhoto(0)
        ..removePhoto(0); // → [c] — 거절된 칸 번호 2 는 이제 없다
      repository.holdAt[2]!.complete();
      await submitting;

      final state = container.read(photosViewModelProvider);
      expect(paths(), isEmpty);
      expect(state.documentRejected, isTrue);
      expect(state.error, isNull, reason: '알 수 없는 오류로 떨어지지 않는다');
    });

    test('모르는 code 는 지금처럼 서버 문구를 그대로 보이고 사진은 그대로다', () async {
      final viewModel = await threePhotos();
      repository.resultAt[1] = const FailureResult(ServerRejectedFailure('부적절한 사진이에요', code: 'photo_unsafe'));

      await viewModel.submit();

      final state = container.read(photosViewModelProvider);
      expect(state.documentRejected, isFalse);
      expect(state.error, _rejected('부적절한 사진이에요'));
      expect(paths(), ['a.jpg', 'b.jpg', 'c.jpg']);
    });
  });

  group('임시 저장', () {
    late FakeDraftStore drafts;
    late Directory dir;
    late List<File> files;

    setUp(() {
      drafts = FakeDraftStore();
      // 얼굴 확인 · 압축이 끝난 사진은 임시 폴더에 있다 — 진짜 파일이어야 "남아 있는지" 를 볼 수 있다.
      dir = Directory.systemTemp.createTempSync('photos_draft');
      // 서로 다른 사진이다 — 바이트가 같으면 같은 사진으로 막힌다.
      files = [for (final name in ['a.jpg', 'b.jpg', 'c.jpg']) File('${dir.path}/$name')..writeAsStringSync(name)];
    });
    tearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    /// 앱을 다시 연 것처럼 새 컨테이너(새 뷰모델)를 만든다. 저장소는 같은 것을 쓴다.
    ProviderContainer open({DraftStore? store}) {
      final opened = ProviderContainer(
        overrides: [
          photosRepositoryProvider.overrideWithValue(repository),
          imageCompressorProvider.overrideWithValue(imageCompressor),
          faceDetectorProvider.overrideWithValue(faceDetector),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          avatarRepositoryProvider.overrideWithValue(avatarRepository),
          draftStoreProvider.overrideWithValue(store ?? drafts),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    /// 세 장을 고르고 [avatar] 번째를 아바타로 정한다.
    Future<PhotosViewModel> pickThree(ProviderContainer opened, {int avatar = 1}) async {
      final vm = opened.read(photosViewModelProvider.notifier)..pickFromGallery = (limit) async => files;
      await vm.addPhoto();
      vm.setAvatarSource(avatar);
      return vm;
    }

    List<String> pathsOf(ProviderContainer opened) =>
        [for (final photo in opened.read(photosViewModelProvider).photos) photo.file!.path];

    test('고른 사진의 경로와 아바타 선택이 저장되고 새로 만들면 돌아온다', () async {
      await pickThree(open());

      final reopened = open();
      expect(pathsOf(reopened), [for (final file in files) file.path]);
      final avatar = [for (final photo in reopened.read(photosViewModelProvider).photos) photo.isAvatarSource];
      expect(avatar, [false, true, false]);
    });

    test('되살린 사진과 같은 사진을 다시 고르면 막힌다 — 원본 해시도 함께 남긴다', () async {
      await pickThree(open());
      final reopened = open();
      final again = File('${dir.path}/a-again.jpg')..writeAsStringSync('a.jpg'); // files[0] 과 바이트가 같다
      final vm = reopened.read(photosViewModelProvider.notifier)..pickFromGallery = (limit) async => [again];

      await vm.addPhoto();

      expect(pathsOf(reopened), [for (final file in files) file.path]);
      expect(reopened.read(photosViewModelProvider).error, isA<PhotoDuplicateFailure>());
    });

    test('해시가 없는 옛 임시 저장도 그대로 되살린다', () async {
      drafts.write(DraftScreen.photos, {
        'photos': [
          {'path': files[0].path, 'isAvatarSource': true},
        ],
      });

      final restored = open().read(photosViewModelProvider).photos.single;
      expect((restored.file!.path, restored.isAvatarSource, restored.sourceHash), (files[0].path, true, null));
    });

    test('복원한 사진은 얼굴 확인 · 압축을 다시 하지 않는다', () async {
      await pickThree(open());
      final compressedBefore = imageCompressor.compressedSources.length;

      open().read(photosViewModelProvider);

      expect(imageCompressor.compressedSources, hasLength(compressedBefore));
    });

    test('사라진 파일은 그 칸만 비우고 남은 사진은 돌려준다', () async {
      await pickThree(open(), avatar: 2);
      files[0].deleteSync(); // 시스템이 임시 폴더를 비운 경우

      final reopened = open();
      expect(pathsOf(reopened), [files[1].path, files[2].path]);
      final avatar = [for (final photo in reopened.read(photosViewModelProvider).photos) photo.isAvatarSource];
      expect(avatar, [false, true], reason: '아바타로 고른 사진이 남아 있으면 선택도 그대로다');
    });

    test('아바타로 고른 사진이 사라지면 아바타 선택은 비어 04-3 에서 다시 고른다', () async {
      await pickThree(open(), avatar: 0);
      files[0].deleteSync();

      final restored = open().read(photosViewModelProvider);
      expect(restored.photos.where((photo) => photo.isAvatarSource), isEmpty);
    });

    test('저장할 때 사진 파일을 딸린 파일로 함께 적는다', () async {
      await pickThree(open());

      expect(drafts.files['account-a/${DraftScreen.photos.key}'], [for (final file in files) file.path]);
    });

    test('"다음" 이 성공하면 저장 정보와 그 임시 파일을 함께 지운다', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      // 고른 사진은 시스템 임시 폴더 아래에 있다 — 앱 임시 폴더 자리로 그 폴더를 준다.
      final store = SharedPreferencesDraftStore(
        preferences,
        accountId: () => 'account-a',
        fileDirectory: Directory.systemTemp.path,
        debounce: Duration.zero,
      );
      final vm = await pickThree(open(store: store));

      await vm.submit();

      expect(open(store: store).read(photosViewModelProvider).photos, isEmpty);
      expect(files.where((file) => file.existsSync()), isEmpty);
    });

    test('아바타 등록이 막혀 04-3 에 머물면 사진은 남는다(다시 올려야 한다)', () async {
      avatarRepository.nextResult = const FailureResult(ServerRejectedFailure('아바타 원본 사진을 먼저 골라 주세요'));
      final vm = await pickThree(open());

      await vm.submit();

      expect(drafts.cleared, isEmpty);
      expect(pathsOf(open()), hasLength(3));
    });
  });

  // 사용 통계 onboarding_blocked — 사진 화면(04-2 · 04-3)에서 막힌 이유를 정해진 종류값으로만 남긴다.
  group('가입 막힘 분석(onboarding_blocked)', () {
    Future<PhotosViewModel> twoPhotos() async {
      await standAt(container, onboardingRepository, OnboardingStep.photos);
      final viewModel = buildViewModel([File('a.jpg'), File('b.jpg')]);
      await viewModel.addPhoto();
      await viewModel.addPhoto();
      viewModel.setAvatarSource(0);
      return viewModel;
    }

    test('글자 많은 사진(서류) 거절은 photo_document', () async {
      final viewModel = await twoPhotos();
      repository.nextResult = const FailureResult(ServerRejectedFailure('서버 임시 문구', code: photoLooksLikeDocumentCode));

      await viewModel.submit();

      expect(analytics.calls, ['onboarding_blocked:photos:photo_document']);
    });

    test('그 밖의 서버 사진 거절은 photo_rejected — 서버 문구는 싣지 않는다', () async {
      final viewModel = await twoPhotos();
      repository.nextResult = const FailureResult(ServerRejectedFailure('부적절한 사진이에요', code: 'photo_unsafe'));

      await viewModel.submit();

      expect(analytics.calls, ['onboarding_blocked:photos:photo_rejected']);
    });

    test('인터넷 문제로 올리지 못하면 network', () async {
      final viewModel = await twoPhotos();
      repository.nextResult = const FailureResult(NetworkFailure());

      await viewModel.submit();

      expect(analytics.calls, ['onboarding_blocked:photos:network']);
    });

    test('고른 사진에서 얼굴을 한 장도 못 찾으면 photo_no_face', () async {
      await standAt(container, onboardingRepository, OnboardingStep.photos);
      final viewModel = buildViewModel([File('a.jpg')]);
      faceDetector.nextResult = false;

      await viewModel.addPhoto();

      expect(analytics.calls, ['onboarding_blocked:photos:photo_no_face']);
    });

    test('일부만 빠지고 한 장이라도 담았으면 막힌 것이 아니다', () async {
      await standAt(container, onboardingRepository, OnboardingStep.photos);
      final viewModel = container.read(photosViewModelProvider.notifier);
      viewModel.pickFromGallery = (limit) async => [File('a.jpg'), File('b.jpg')];
      faceDetector.queuedResults.addAll([true, false]);

      await viewModel.addPhoto();

      expect(analytics.calls, isEmpty);
    });

    test('가입이 끝난 뒤(15-7 사진 수정이 같은 뷰모델을 쓴다)의 실패는 가입 막힘이 아니다', () async {
      final viewModel = buildViewModel([File('a.jpg')]);
      await viewModel.addPhoto();
      viewModel.setAvatarSource(0);
      repository.nextResult = const FailureResult(NetworkFailure());

      await viewModel.submit();

      expect(analytics.calls, isEmpty);
    });
  });

}

final _noFace = isA<AppErrorFailure>().having((failure) => failure.error, 'error', AppError.noFace);

Matcher _rejectedCount(int count) => isA<PhotoRejectedFailure>().having((failure) => failure.count, 'count', count);

Matcher _rejected(String message) =>
    isA<ServerRejectedFailure>().having((failure) => failure.serverMessage, 'serverMessage', message);
