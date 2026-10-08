import 'dart:io';

import 'package:flutter/painting.dart';

/// [PhotosUiState.copyWith] 에서 "안 넘긴 것"과 "null 로 지우는 것"을 가르는 표시(school_info_view_model 과 같은 방식).
const Object _keep = Object();

/// 칸의 사진 한 장 + 아바타 원본 여부. 온보딩(04-2 · 04-3)은 늘 이번에 고른 사진이고, 15-7 사진 수정은 이미 올려 둔
/// 사진([SelectedPhoto.saved])과 섞인다(계획서 2026-09-27-me-edit.md A6).
class SelectedPhoto {
  const SelectedPhoto(File this.file, {this.isAvatarSource = false}) : id = null, url = null;
  const SelectedPhoto.saved({required String this.id, required String this.url, this.isAvatarSource = false})
      : file = null;

  /// 이번에 고른 사진. 이미 올려 둔 사진(15-7 편집)이면 null.
  final File? file;

  /// 이미 올려 둔 사진의 행 id · 서명 주소. 새로 고른 사진이면 null.
  final String? id;
  final String? url;
  final bool isAvatarSource;

  /// 끌기에서 사진을 가리키는 열쇠. 새 사진은 파일 경로, 올려 둔 사진은 행 id.
  String get key => id ?? file!.path;

  ImageProvider get image => file != null ? FileImage(file!) : NetworkImage(url!);

  SelectedPhoto copyWith({bool? isAvatarSource}) => file != null
      ? SelectedPhoto(file!, isAvatarSource: isAvatarSource ?? this.isAvatarSource)
      : SelectedPhoto.saved(id: id!, url: url!, isAvatarSource: isAvatarSource ?? this.isAvatarSource);
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

  /// 한 번에 올릴 수 있는 최대 장수.
  static const int maxPhotos = 4;

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

  /// 이번에 고른 사진(파일이 있는 칸)만 — 이미 올려 둔 사진은 15-7 편집에만 있고 임시 저장 대상이 아니다.
  Iterable<SelectedPhoto> get _pickedPhotos => photos.where((photo) => photo.file != null);

  /// 폰에 임시 저장할 값 — 고른 사진의 **파일 경로**와 아바타 원본 표시. 사진 자체는 임시 폴더에 그대로 있다.
  Map<String, Object?> toDraft() => {
        'photos': [
          for (final photo in _pickedPhotos) {'path': photo.file!.path, 'isAvatarSource': photo.isAvatarSource},
        ],
      };

  /// [toDraft] 와 함께 지울 파일 — "다음" 성공 · 로그아웃 · 탈퇴 때 저장 정보와 같이 지운다.
  List<String> get draftFiles => [for (final photo in _pickedPhotos) photo.file!.path];

  /// [toDraft] 로 남긴 경로 중 **파일이 남아 있는 것만** 칸에 넣는다(시스템이 임시 폴더를 비웠을 수 있다).
  /// 이미 얼굴 확인 · 압축이 끝난 파일이라 다시 처리하지 않는다. 아바타 원본은 많아야 한 장만 살린다 —
  /// 그 사진이 사라졌으면 비워 두고, 04-2 → 04-3 으로 넘어갈 때 첫 장이 골라진다. 모양이 안 맞으면 던진다.
  static PhotosUiState fromDraft(Map<String, Object?> data) {
    final saved = [
      for (final item in (data['photos'] as List).cast<Map<String, Object?>>())
        SelectedPhoto(File(item['path'] as String), isAvatarSource: item['isAvatarSource'] as bool),
    ];
    final kept = saved.where((photo) => photo.file!.existsSync()).take(maxPhotos).toList();
    final avatar = kept.indexWhere((photo) => photo.isAvatarSource);
    return PhotosUiState(photos: [for (var i = 0; i < kept.length; i++) kept[i].copyWith(isAvatarSource: i == avatar)]);
  }
}
