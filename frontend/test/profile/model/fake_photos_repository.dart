import 'dart:async';
import 'dart:io';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/photos_repository.dart';

class FakeUpload {
  FakeUpload(this.photo, this.position, this.isAvatarSource);

  final File photo;
  final int position;
  final bool isAvatarSource;
}

class FakePhotosRepository implements PhotosRepository {
  Result<void> nextResult = const Success(null);

  /// 칸(position)마다 다른 결과 — 없으면 [nextResult].
  final Map<int, Result<void>> resultAt = {};

  /// 칸(position)마다 채워 두면 그 칸 올리기가 여기서 멈춘다 — "올리는 중에 목록이 바뀌는" 상황용.
  final Map<int, Completer<void>> holdAt = {};
  final List<FakeUpload> uploads = [];

  @override
  Future<Result<void>> uploadPhoto(File photo, int position, bool isAvatarSource) async {
    uploads.add(FakeUpload(photo, position, isAvatarSource));
    await holdAt[position]?.future;
    return resultAt[position] ?? nextResult;
  }
}
