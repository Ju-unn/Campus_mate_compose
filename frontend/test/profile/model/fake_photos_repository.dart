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
  final List<FakeUpload> uploads = [];

  @override
  Future<Result<void>> uploadPhoto(File photo, int position, bool isAvatarSource) async {
    uploads.add(FakeUpload(photo, position, isAvatarSource));
    return nextResult;
  }
}
