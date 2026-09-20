import 'dart:io';

import 'package:campus_mate/common/result.dart';

abstract interface class PhotosRepository {
  Future<Result<void>> uploadPhoto(File photo, int position, bool isAvatarSource);
}
