import 'dart:io';

/// 15e 사진 수정의 칸 하나(계획서 2026-09-27-me-edit.md 2-2 · U2). 칸 순서 그대로 `PUT /me/photos` 의 `layout` 이 된다 —
/// 이미 올려 둔 사진은 행 id 로 남기고([KeptPhoto]), 이번에 고른 사진은 파일로 새로 올린다([NewPhoto]).
sealed class PhotoSlot {
  const PhotoSlot();
}

/// 이미 올려 둔 사진 — 서버가 행 id 그대로 자리만 옮긴다.
final class KeptPhoto extends PhotoSlot {
  const KeptPhoto(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is KeptPhoto && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 이번에 고른 사진 — 압축을 마친 파일.
final class NewPhoto extends PhotoSlot {
  const NewPhoto(this.file);

  final File file;

  @override
  bool operator ==(Object other) => other is NewPhoto && other.file.path == file.path;

  @override
  int get hashCode => file.path.hashCode;
}
