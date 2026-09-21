import 'dart:io';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/profile/model/photos_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [PhotosRepository]를 FastAPI 호출로 구현한다. 사진 1장당 요청 1개(Task B9 router.py 와 1:1 대응).
class HttpPhotosRepository implements PhotosRepository {
  const HttpPhotosRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<void>> uploadPhoto(File photo, int position, bool isAvatarSource) async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) async => http.MultipartRequest('POST', Uri.parse('$_baseUrl/profile-onboarding/photos'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['position'] = position.toString()
      ..fields['is_avatar_source'] = isAvatarSource.toString()
      ..files.add(await http.MultipartFile.fromPath('photo', photo.path)),
    );
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
