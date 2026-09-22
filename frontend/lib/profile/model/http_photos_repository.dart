import 'dart:io';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/photos_repository.dart';

/// [PhotosRepository]를 FastAPI 호출로 구현한다. 사진 1장당 요청 1개(Task B9 router.py 와 1:1 대응).
/// 본문이 multipart 라 JSON 지름길([ApiClient.send])이 아니라 요청을 직접 만든다.
class HttpPhotosRepository implements PhotosRepository {
  const HttpPhotosRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> uploadPhoto(File photo, int position, bool isAvatarSource) async {
    final result = await _api.sendMultipart(
      '/profile-onboarding/photos',
      {'position': position.toString(), 'is_avatar_source': isAvatarSource.toString()},
      photo.path,
    );
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
