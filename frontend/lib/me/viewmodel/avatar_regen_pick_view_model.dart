import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

final avatarRegenPickViewModelProvider =
    NotifierProvider.autoDispose<AvatarRegenPickViewModel, AvatarRegenPickUiState>(AvatarRegenPickViewModel.new);

/// 15b-4 / 15b-5 "아바타 다시 만들기 · 사진 고르기"의 상태.
class AvatarRegenPickUiState {
  const AvatarRegenPickUiState({
    this.photo,
    this.isChecking = false,
    this.isSubmitting = false,
    this.photoReplaced = false,
    this.errorMessage,
    this.completed = false,
  });

  /// 새로 고른 사진(압축 · 얼굴 검사를 마친 것). 없으면 15b-4(빈 칸), 있으면 15b-5.
  final File? photo;

  /// 고른 사진에 얼굴이 있는지 살펴보는 중.
  final bool isChecking;

  /// 사진을 바꾸고 아바타를 등록하는 중.
  final bool isSubmitting;

  /// 새 사진이 이미 서버의 아바타 원본으로 바뀌었다 — 이때 등록이 막히면 다시 누를 때 사진은 다시 올리지 않고 등록만 한다.
  final bool photoReplaced;

  final String? errorMessage;

  /// 아바타 등록까지 끝났다 — 화면은 15 로 돌아가고, 그림은 15 가 만드는 중 안내로 기다린다.
  final bool completed;

  /// "이 사진으로 아바타 만들기" 를 누를 수 있는지.
  bool get canSubmit => photo != null && !isChecking && !isSubmitting;

  AvatarRegenPickUiState copyWith({
    Object? photo = _keep,
    bool? isChecking,
    bool? isSubmitting,
    bool? photoReplaced,
    Object? errorMessage = _keep,
    bool? completed,
  }) {
    return AvatarRegenPickUiState(
      photo: identical(photo, _keep) ? this.photo : photo as File?,
      isChecking: isChecking ?? this.isChecking,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      photoReplaced: photoReplaced ?? this.photoReplaced,
      errorMessage: identical(errorMessage, _keep) ? this.errorMessage : errorMessage as String?,
      completed: completed ?? this.completed,
    );
  }
}

const Object _keep = Object();

/// 열려 있는 화면 15 수(15 가 열리고 닫힐 때 센다). 아바타 뷰모델의 폴링 타이머는 하나라, 등록 응답을 기다리는 사이 화면 15 가 모두
/// 닫혔으면 뒤늦게 시작된 폴링을 우리가 끊어야 하고, 하나라도 열려 있으면 그 화면이 쥐고 있으니 그대로 둔다.
int openMyProfileScreens = 0;

/// 갤러리에서 사진 한 장. image_picker 는 플랫폼 플러그인이라 단위 테스트에서 부를 수 없어 훅으로 갈아끼운다
/// ([PhotosViewModel] 과 같은 패턴). 고르지 않고 닫으면 null.
Future<File?> _pickOne() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  return picked == null ? null : File(picked.path);
}

/// 새 사진을 먼저 고르고, 그 사진이 지금 아바타 원본 사진을 **대신한다**(사용자 결정 2026-10-08) — 실제 사진 목록의 "원본 칸"
/// 하나가 새 파일로 바뀌어 장수는 그대로다. 순서는 사진 교체(`PUT /me/photos`) → 아바타 등록(`POST /me/avatar/regenerate`).
/// 하트는 서버가 아바타가 다 만들어진 뒤에 뺀다 — 여기서 건드리지 않는다. 하트 확인 시트는 화면이 이 [submit] 앞에서 보인다.
class AvatarRegenPickViewModel extends Notifier<AvatarRegenPickUiState> {
  Future<File?> Function() pickFromGallery = _pickOne;

  @override
  AvatarRegenPickUiState build() => const AvatarRegenPickUiState();

  /// 사진 칸을 누르면 갤러리에서 한 장 고른다(15b-5 에서 다시 누르면 바꾼다). 고르지 않고 닫거나 갤러리가 열리지 않으면(권한 거부 등)
  /// 아무 일도 하지 않는다 — 04-2 와 같다. 얼굴이 안 보이면 칸에 넣지 않고 같은 문구로 알린다.
  Future<void> pick() async {
    if (state.isChecking || state.isSubmitting) {
      return;
    }
    final file = await _pickOrNull();
    if (file == null) {
      return;
    }
    state = state.copyWith(isChecking: true, errorMessage: null);
    var accepted = state.photo;
    String? message;
    try {
      final checked = await _checked(file);
      if (checked == null) {
        message = '얼굴이 보이는 사진을 골라 주세요';
      } else {
        accepted = checked;
      }
    } finally {
      // 새 사진으로 바꾸면 서버에 이미 올린 사진은 이 사진이 아니다 — 다시 올려야 한다.
      state = state.copyWith(
        photo: accepted,
        isChecking: false,
        errorMessage: message,
        photoReplaced: accepted == state.photo ? state.photoReplaced : false,
      );
    }
  }

  /// 갤러리 자체가 실패하면(권한 거부 등) 고르지 않고 닫은 것과 같이 다룬다.
  Future<File?> _pickOrNull() async {
    try {
      return await pickFromGallery();
    } on Exception {
      return null;
    }
  }

  /// 압축한 사진. 얼굴이 없거나 사진을 처리하지 못하면 null. 얼굴 검사가 예외를 던지면 통과시킨다(04-2 와 같다 —
  /// 기기 안 검사는 1차 필터이고 서버 SafeSearch 가 다시 본다).
  Future<File?> _checked(File file) async {
    try {
      final compressed = await ref.read(imageCompressorProvider).compressToJpeg(file);
      try {
        return await ref.read(faceDetectorProvider).hasFace(compressed) ? compressed : null;
      } on Exception {
        return compressed;
      }
    } on Exception {
      return null;
    }
  }

  /// 하트 확인을 마친 뒤 부른다. 사진 교체가 먼저고, 실패하면 등록은 부르지 않는다. 교체가 끝난 뒤 등록이 막히면 새 사진은 이미
  /// 원본으로 남아 있어, 문구를 보여 주고 다시 누르면 등록만 다시 한다.
  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    // 올리는 도중에 뒤로 나가도 끝까지 마치고 15 가 이어받게 한다 — 그동안 autoDispose 가 버리지 않게 붙잡는다(15-7 저장과 같다).
    final keepAlive = ref.keepAlive();
    try {
      if (!state.photoReplaced) {
        final failure = await _replaceSource(state.photo!);
        if (failure != null) {
          state = state.copyWith(isSubmitting: false, errorMessage: failure);
          return;
        }
        state = state.copyWith(photoReplaced: true);
      }
      final avatar = ref.read(avatarGenerationViewModelProvider.notifier);
      final blocking = await avatar.regenerate();
      // 등록 응답을 기다리는 사이 화면 15 까지 떠났으면 방금 걸린 폴링을 끊는다 — 15 의 dispose 는 이미 지나갔다.
      if (openMyProfileScreens == 0) avatar.stopPolling();
      state = blocking == null
          ? state.copyWith(isSubmitting: false, completed: true)
          : state.copyWith(isSubmitting: false, errorMessage: blocking);
    } catch (_) {
      state = state.copyWith(isSubmitting: false, errorMessage: const UnknownFailure().toDisplayMessage());
    } finally {
      keepAlive.close();
    }
  }

  /// 원본 칸을 새 파일로 바꾸고 나머지는 그대로 둔다. 실패 문구(없으면 null)는 15-7 사진 저장과 같은 서버 문구를 쓴다.
  Future<String?> _replaceSource(File file) async {
    final profile = await ref.read(myProfileProvider.future);
    final photos = profile.when<List<MyPhoto>?>(onSuccess: (p) => p.photos, onFailure: (_) => null);
    if (photos == null || photos.isEmpty) {
      return const UnknownFailure().toDisplayMessage();
    }
    final sourceIndex = photos.indexWhere((p) => p.isAvatarSource);
    final replaced = sourceIndex < 0 ? 0 : sourceIndex;
    final slots = <PhotoSlot>[
      for (final (index, photo) in photos.indexed) index == replaced ? NewPhoto(file) : KeptPhoto(photo.id),
    ];
    final result = await ref.read(meRepositoryProvider).savePhotos(slots, replaced);
    // 실패해도 다시 읽는다 — 서버는 여러 요청으로 나눠 바꿔 중간에 멈출 수 있다(15-7 과 같다).
    ref.invalidate(myProfileProvider);
    return result.when(onSuccess: (_) => null, onFailure: (failure) => failure.toDisplayMessage());
  }
}
