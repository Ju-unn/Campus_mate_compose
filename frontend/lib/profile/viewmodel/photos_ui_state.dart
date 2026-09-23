import 'dart:io';

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
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final List<SelectedPhoto> photos;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  /// 04-2 "다음"으로 04-3 에 갈 수 있는지.
  bool get canProceed => photos.length >= 2 && photos.length <= 4;

  /// 04-3 에서 올릴 수 있는지.
  bool get canSubmit => !isSubmitting && canProceed && photos.where((p) => p.isAvatarSource).length == 1;
}
