import 'dart:io';

/// [PhotosUiState.copyWith] 에서 "안 넘긴 것"과 "null 로 지우는 것"을 가르는 표시(school_info_view_model 과 같은 방식).
const Object _keep = Object();

/// 고른 사진 한 장 + 아바타 원본 여부.
class SelectedPhoto {
  const SelectedPhoto(this.file, {this.isAvatarSource = false});

  final File file;
  final bool isAvatarSource;

  SelectedPhoto copyWith({bool? isAvatarSource}) {
    return SelectedPhoto(file, isAvatarSource: isAvatarSource ?? this.isAvatarSource);
  }
}

/// 사진 업로드(04-2)와 아바타 사진 고르기(04-3)가 함께 쓰는 상태. 최소 2장·최대 4장, 그중 정확히 1장이 아바타 원본.
/// 04-2 에서는 고르기만 하고, 04-3 에서 원본을 정한 뒤 한 번에 올린다 — 서버가 업로드할 때 원본 여부를 같이 받는다.
class PhotosUiState {
  const PhotosUiState({
    this.photos = const [],
    this.isCheckingPhotos = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final List<SelectedPhoto> photos;

  /// 고른 사진에 얼굴이 있는지 살펴보는 중. 빈 칸 하나가 기다리는 표시로 바뀐다.
  final bool isCheckingPhotos;

  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  /// 넘긴 것만 바꿌 새 상태를 만든다. 사진을 고르는 동안 04-3 에서 제출이 같이 돌 수 있어,
  /// 한쪽이 손대지 않은 표시(특히 [isSubmitting])를 지우면 같은 사진을 두 번 올릴 수 있다.
  PhotosUiState copyWith({
    List<SelectedPhoto>? photos,
    bool? isCheckingPhotos,
    bool? isSubmitting,
    Object? errorMessage = _keep,
    bool? completed,
  }) {
    return PhotosUiState(
      photos: photos ?? this.photos,
      isCheckingPhotos: isCheckingPhotos ?? this.isCheckingPhotos,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: identical(errorMessage, _keep) ? this.errorMessage : errorMessage as String?,
      completed: completed ?? this.completed,
    );
  }

  /// 04-2 "다음"으로 04-3 에 갈 수 있는지.
  bool get canProceed => photos.length >= 2 && photos.length <= 4;

  /// 04-3 에서 올릴 수 있는지.
  bool get canSubmit => !isSubmitting && canProceed && photos.where((p) => p.isAvatarSource).length == 1;
}
