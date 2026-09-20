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

/// 사진 업로드 화면(DESIGN.md 화면 04-2)의 상태. 최소 2장·최대 4장, 그중 정확히 1장이 아바타 원본.
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

  bool get canSubmit {
    return !isSubmitting &&
        photos.length >= 2 &&
        photos.length <= 4 &&
        photos.where((p) => p.isAvatarSource).length == 1;
  }
}
