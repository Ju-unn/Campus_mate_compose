import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/photos_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

final photosViewModelProvider = NotifierProvider<PhotosViewModel, PhotosUiState>(
  PhotosViewModel.new,
);

const _maxPhotos = 4;

/// 갤러리에서 사진 한 장을 고른다. image_picker 는 플랫폼 플러그인이라 단위 테스트에서 부를 수 없어
/// [PhotosViewModel.pickFromGallery] 훅으로 갈아끼운다(조각1b StudentVerificationViewModel 과 같은 패턴).
Future<File?> _pickFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  return picked == null ? null : File(picked.path);
}

/// 사진 업로드(04-2)와 아바타 사진 고르기(04-3)의 흐름을 맡는다. 두 화면이 같은 상태를 이어 쓴다.
class PhotosViewModel extends Notifier<PhotosUiState> {
  Future<File?> Function() pickFromGallery = _pickFromGallery;

  @override
  PhotosUiState build() => const PhotosUiState();

  /// 갤러리에서 사진을 골라 압축해 담는다. 고르지 않고 닫으면 아무 일도 하지 않는다.
  /// 이미 4장이면 말없이 무시하지 않고 왜 안 되는지 알려 준다(2026-09-20 리뷰 제안 d).
  Future<void> addPhoto() async {
    if (state.photos.length >= _maxPhotos) {
      state = PhotosUiState(photos: state.photos, errorMessage: '사진은 최대 $_maxPhotos장까지 올릴 수 있어요');
      return;
    }
    final picked = await pickFromGallery();
    if (picked == null) {
      return;
    }
    final compressed = await ref.read(imageCompressorProvider).compressToJpeg(picked);
    state = PhotosUiState(
      photos: [...state.photos, SelectedPhoto(compressed)],
      errorMessage: null,
    );
  }

  void removePhoto(int index) {
    final photos = [...state.photos]..removeAt(index);
    state = PhotosUiState(photos: photos, errorMessage: null);
  }

  /// 길게 눌러 끌어다 놓으면 두 칸이 자리를 맞바꾼다(04-2, 2026-09-24 사용자 결정).
  /// 대표는 **첫 칸**이라, 대표를 바꾸려면 그 사진을 첫 칸으로 끌면 된다 —
  /// 종전에는 앞 사진을 전부 지워야 했다. 올릴 때 position 이 이 순서를 그대로 따라간다.
  void swapPhotos(int from, int to) {
    final count = state.photos.length;
    if (from == to || from < 0 || to < 0 || from >= count || to >= count) {
      return; // 빈 칸으로는 끌 수 없다 — 순서에 구멍이 나면 업로드 position 이 어긋난다.
    }
    final photos = [...state.photos];
    photos[from] = state.photos[to];
    photos[to] = state.photos[from];
    state = PhotosUiState(photos: photos, errorMessage: null);
  }

  /// 아바타 원본은 한 장만 고를 수 있다 — 나머지는 자동으로 꺼진다.
  void setAvatarSource(int index) {
    final photos = [
      for (var i = 0; i < state.photos.length; i++) state.photos[i].copyWith(isAvatarSource: i == index),
    ];
    state = PhotosUiState(photos: photos, errorMessage: null);
  }

  /// 04-2 → 04-3 으로 넘어갈 때 부른다. 아직 원본이 없으면(처음이거나 원본 사진을 뺐으면) 첫 장을 골라 둔다.
  void prepareAvatarSource() {
    if (state.photos.isEmpty || state.photos.any((p) => p.isAvatarSource)) {
      return;
    }
    setAvatarSource(0);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = PhotosUiState(photos: state.photos, isSubmitting: true);
    state = await _submittedState();
    _refreshOnboardingStepIfCompleted();
  }

  Future<PhotosUiState> _submittedState() async {
    try {
      final repository = ref.read(photosRepositoryProvider);
      for (var position = 0; position < state.photos.length; position++) {
        final photo = state.photos[position];
        final result = await repository.uploadPhoto(photo.file, position, photo.isAvatarSource);
        final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
        if (failure != null) {
          return PhotosUiState(photos: state.photos, errorMessage: failure.toDisplayMessage());
        }
      }
      return PhotosUiState(photos: state.photos, completed: true);
    } catch (_) {
      return PhotosUiState(photos: state.photos, errorMessage: const UnknownFailure().toDisplayMessage());
    }
  }

  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
