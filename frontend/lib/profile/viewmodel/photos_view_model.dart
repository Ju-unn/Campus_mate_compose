import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
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

/// 갤러리에서 남은 칸 수([limit])만큼 고른다 — 화면 안내대로 여러 장을 한 번에 고를 수 있다.
/// image_picker 는 플랫폼 플러그인이라 단위 테스트에서 부를 수 없어
/// [PhotosViewModel.pickFromGallery] 훅으로 갈아끼운다(조각1b StudentVerificationViewModel 과 같은 패턴).
Future<List<File>> _pickFromGallery(int limit) async {
  final picked = await ImagePicker().pickMultiImage(limit: limit);
  return [for (final image in picked) File(image.path)];
}

/// 사진 업로드(04-2)와 아바타 사진 고르기(04-3)의 흐름을 맡는다. 두 화면이 같은 상태를 이어 쓴다.
class PhotosViewModel extends Notifier<PhotosUiState> {
  Future<List<File>> Function(int limit) pickFromGallery = _pickFromGallery;

  @override
  PhotosUiState build() => const PhotosUiState();

  /// 갤러리에서 사진을 골라 압축해 담는다. 고르지 않고 닫으면 아무 일도 하지 않는다.
  /// 이미 4장이면 말없이 무시하지 않고 왜 안 되는지 알려 준다(2026-09-20 리뷰 제안 d).
  ///
  /// 얼굴이 보이지 않는 사진은 칸에 넣지 않는다(2026-09-24 사용자 결정 — 04-2 도 3b 처럼 기기 안에서 먼저 본다).
  /// 여러 장을 한 번에 골랐으면 얼굴이 있는 것만 들어가고, 빠진 장수를 문구로 알려 준다.
  /// 살펴보는 동안 다시 누르면 남은 칸을 두 번 세어 4장을 넘겨 버리고, 그러면 "다음"이 영영 켜지지 않는다.
  /// 먼저 시작한 쪽이 끝날 때까지 같은 작업을 돌려준다(push_registrar 와 같은 방식).
  /// `state.isCheckingPhotos` 는 그 사이 removePhoto·swapPhotos 가 지워 버려 가드로 쓸 수 없다.
  Future<void> addPhoto() => _adding ??= _addPhoto().whenComplete(() => _adding = null);

  Future<void>? _adding;

  Future<void> _addPhoto() async {
    final room = _maxPhotos - state.photos.length;
    if (room <= 0) {
      state = state.copyWith(errorMessage: '사진은 최대 $_maxPhotos장까지 올릴 수 있어요');
      return;
    }
    final picked = await _pickOrEmpty(room);
    if (picked.isEmpty) {
      return;
    }
    state = state.copyWith(isCheckingPhotos: true, errorMessage: null);
    final accepted = <SelectedPhoto>[];
    var rejected = 0;
    try {
      for (final file in picked.take(room)) {
        final photo = await _checkedPhoto(file);
        if (photo != null) {
          accepted.add(photo);
        } else {
          rejected++;
        }
      }
    } finally {
      // 중간에 무엇이 터지든 기다리는 표시는 반드시 내린다 — 굳으면 칸이 빈 채로 남는다.
      state = state.copyWith(
        photos: [...state.photos, ...accepted],
        isCheckingPhotos: false,
        errorMessage: _rejectedMessage(accepted.length, rejected),
      );
    }
  }

  /// 갤러리 자체가 실패하면(권한 거부 등 `PlatformException`) 고르지 않고 닫은 것과 같이 다룬다.
  Future<List<File>> _pickOrEmpty(int limit) async {
    try {
      return await pickFromGallery(limit);
    } on Exception {
      return const [];
    }
  }

  /// 압축한 사진을 돌려준다. 얼굴이 없거나 사진 자체를 처리하지 못하면 `null` — 둘 다 '빠진 장'으로 센다
  /// (3b `_compressedPhotoWithFace` 와 같은 모양). 압축이 try 밖에 있으면 기다리는 표시가 굳는다.
  Future<SelectedPhoto?> _checkedPhoto(File file) async {
    try {
      final compressed = await ref.read(imageCompressorProvider).compressToJpeg(file);
      return await _hasFace(compressed) ? SelectedPhoto(compressed) : null;
    } on Exception {
      return null;
    }
  }

  /// 얼굴을 못 찾은 것과 **검사 자체가 실패한 것**은 다르다 — ML Kit 이 예외를 던지면 통과시킨다.
  /// 기기 안 검사는 1차 필터일 뿐이고 올릴 때 서버 SafeSearch 가 다시 본다(설계 §7.3).
  /// 검출기가 고장 났다고 사진을 한 장도 못 고르게 막는 쪽이 더 나쁘다.
  Future<bool> _hasFace(File photo) async {
    try {
      return await ref.read(faceDetectorProvider).hasFace(photo);
    } on Exception {
      return true;
    }
  }

  /// 한 장도 못 들어갔으면 "다시 고르라"고, 일부만 빠졌으면 몇 장이 빠졌는지 알린다(2026-09-25 사용자 결정).
  String? _rejectedMessage(int accepted, int rejected) {
    if (rejected == 0) {
      return null;
    }
    return accepted == 0 ? '얼굴이 보이는 사진을 골라 주세요' : '$rejected장은 얼굴이 보이지 않아 빠졌어요';
  }

  void removePhoto(int index) {
    final photos = [...state.photos]..removeAt(index);
    state = state.copyWith(photos: photos, errorMessage: null);
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
    state = state.copyWith(photos: photos, errorMessage: null);
  }

  /// 아바타 원본은 한 장만 고를 수 있다 — 나머지는 자동으로 꺼진다.
  void setAvatarSource(int index) {
    final photos = [
      for (var i = 0; i < state.photos.length; i++) state.photos[i].copyWith(isAvatarSource: i == index),
    ];
    state = state.copyWith(photos: photos, errorMessage: null);
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
    state = state.copyWith(isSubmitting: true, errorMessage: null);
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
          return state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage());
        }
      }
      return state.copyWith(isSubmitting: false, completed: true);
    } catch (_) {
      return state.copyWith(isSubmitting: false, errorMessage: const UnknownFailure().toDisplayMessage());
    }
  }

  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }
}
