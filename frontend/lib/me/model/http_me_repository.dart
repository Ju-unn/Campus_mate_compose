import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/me/model/me_repository.dart';
import 'package:campus_mate/me/model/my_profile.dart';

/// [MeRepository] 를 FastAPI `GET /me/profile` 로 구현한다.
class HttpMeRepository implements MeRepository {
  const HttpMeRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<MyProfile>> fetchProfile() => _api.send('GET', '/me/profile', (body) {
        final json = body as Map<String, dynamic>;
        return MyProfile(
          nickname: json['nickname'] as String,
          age: json['age'] as int?,
          university: json['university'] as String,
          major: json['major'] as String?,
          heightCm: json['height_cm'] as int?,
          mbti: json['mbti'] as String?,
          avatarUrl: json['avatar_url'] as String?,
          photoUrls: (json['photo_urls'] as List<dynamic>).cast<String>(),
          preferredAgeMin: json['preferred_age_min'] as int?,
          preferredAgeMax: json['preferred_age_max'] as int?,
          preferredHeightMin: json['preferred_height_min'] as int?,
          preferredHeightMax: json['preferred_height_max'] as int?,
          bio: json['bio'] as String?,
        );
      });
}
