import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/photos_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_face_detector.dart';
import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_avatar_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../model/fake_photos_repository.dart';

void main() {
  late FakePhotosRepository repository;
  late FakeImageCompressor imageCompressor;
  late FakeFaceDetector faceDetector;
  late FakeOnboardingRepository onboardingRepository;
  late FakeAvatarRepository avatarRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakePhotosRepository();
    imageCompressor = FakeImageCompressor();
    faceDetector = FakeFaceDetector();
    onboardingRepository = FakeOnboardingRepository();
    avatarRepository = FakeAvatarRepository();
    container = ProviderContainer(
      overrides: [
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
    expect(state.errorMessage, '얼굴이 보이는 사진을 골라 주세요');
  });

  test('여러 장을 한 번에 고르면 얼굴이 있는 것만 들어간다', () async {
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [File('a.jpg'), File('b.jpg'), File('c.jpg')];
    // 가운데 두 장에 얼굴이 없다.
    faceDetector.queuedResults.addAll([true, false, false]);

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect([for (final photo in state.photos) photo.file.path], ['a.jpg']);
    expect(state.errorMessage, '2장은 얼굴이 보이지 않아 빠졌어요');
  });

  test('일부만 빠지면 몇 장이 빠졌는지 알린다', () async {
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [File('a.jpg'), File('b.jpg')];
    faceDetector.queuedResults.addAll([true, false]);

    await viewModel.addPhoto();

    expect(container.read(photosViewModelProvider).errorMessage, '1장은 얼굴이 보이지 않아 빠졌어요');
  });

  test('한 장도 못 들어가면 장수 대신 다시 고르라고 알린다', () async {
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [File('a.jpg'), File('b.jpg')];
    faceDetector.nextResult = false;

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect(state.photos, isEmpty);
    expect(state.errorMessage, '얼굴이 보이는 사진을 골라 주세요');
  });

  test('압축에 실패한 사진도 빠진 장으로 세고 기다리는 표시를 내린다', () async {
    // 압축이 try 밖에 있으면 예외가 새어 나가 기다리는 표시가 굳는다.
    final viewModel = buildViewModel([File('a.jpg')]);
    imageCompressor.nextError = Exception('사진을 읽지 못했다');

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect(state.photos, isEmpty);
    expect(state.isCheckingPhotos, isFalse);
    expect(state.errorMessage, '얼굴이 보이는 사진을 골라 주세요');
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
    const state = PhotosUiState(isSubmitting: true, errorMessage: '앗');

    final next = state.copyWith(photos: [SelectedPhoto(File('a.jpg'))]);

    expect(next.isSubmitting, isTrue);
    expect(next.errorMessage, '앗');
    expect(next.copyWith(errorMessage: null).errorMessage, isNull);
  });

  test('검출기가 예외를 던지면 막지 않고 통과시킨다', () async {
    // 기기 검사는 1차 필터일 뿐이라, 검출기 장애로 사진을 못 고르게 막는 쪽이 더 나쁘다.
    final viewModel = buildViewModel([File('a.jpg')]);
    faceDetector.nextError = Exception('ML Kit 이 사진을 읽지 못했다');

    await viewModel.addPhoto();

    final state = container.read(photosViewModelProvider);
    expect(state.photos.length, 1);
    expect(state.errorMessage, isNull);
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
    expect(photos[0].file.path, 'b.jpg');
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
    expect([for (final photo in photos) photo.file.path], ['a.jpg', 'b.jpg']);
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

    expect(container.read(photosViewModelProvider).errorMessage, '사진은 최대 4장까지 올릴 수 있어요');
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
    expect(state.errorMessage, '아바타 원본 사진을 먼저 골라 주세요');
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
    expect(container.read(photosViewModelProvider).errorMessage, isNotNull);
  });
}
