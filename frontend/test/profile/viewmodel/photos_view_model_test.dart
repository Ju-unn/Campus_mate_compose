import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/photos_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_onboarding_repository.dart';
import '../model/fake_photos_repository.dart';

void main() {
  late FakePhotosRepository repository;
  late FakeImageCompressor imageCompressor;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakePhotosRepository();
    imageCompressor = FakeImageCompressor();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        photosRepositoryProvider.overrideWithValue(repository),
        imageCompressorProvider.overrideWithValue(imageCompressor),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  PhotosViewModel buildViewModel(List<File> photosToPick) {
    final viewModel = container.read(photosViewModelProvider.notifier);
    var index = 0;
    viewModel.pickFromGallery = () async => photosToPick[index++];
    return viewModel;
  }

  test('사진이 2장 미만이면 제출할 수 없다', () async {
    final viewModel = buildViewModel([File('a.jpg')]);
    await viewModel.addPhoto();
    expect(container.read(photosViewModelProvider).canSubmit, isFalse);
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
