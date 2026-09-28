import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/me/model/me_repository.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// [MeRepository] 를 FastAPI `GET · PATCH /me/profile` 로 구현한다.
class HttpMeRepository implements MeRepository {
  const HttpMeRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<MyProfile>> fetchProfile() => _api.send('GET', '/me/profile', (body) {
        final json = body as Map<String, dynamic>;
        final changeableAt = json['nickname_changeable_at'] as String?;
        return MyProfile(
          nickname: json['nickname'] as String,
          age: json['age'] as int?,
          university: json['university'] as String,
          major: json['major'] as String?,
          heightCm: json['height_cm'] as int?,
          mbti: json['mbti'] as String?,
          avatarUrl: json['avatar_url'] as String?,
          preferredAgeMin: json['preferred_age_min'] as int?,
          preferredAgeMax: json['preferred_age_max'] as int?,
          preferredHeightMin: json['preferred_height_min'] as int?,
          preferredHeightMax: json['preferred_height_max'] as int?,
          bio: json['bio'] as String?,
          photos: [for (final photo in json['photos'] as List<dynamic>) _photo(photo as Map<String, dynamic>)],
          interestTags: (json['interest_tags'] as List<dynamic>).cast<String>(),
          myTraits: (json['my_traits'] as List<dynamic>).cast<String>(),
          idealTraits: (json['ideal_traits'] as List<dynamic>).cast<String>(),
          preferredMbtiFlags: (json['preferred_mbti_flags'] as Map<String, dynamic>).cast<String, bool>(),
          preferredAnimalTypes: [
            for (final name in json['preferred_animal_types'] as List<dynamic>) AnimalType.values.byName(name as String),
          ],
          preferredImpressionTypes: [
            for (final name in json['preferred_impression_types'] as List<dynamic>)
              ImpressionType.values.byName(name as String),
          ],
          heartBalance: json['heart_balance'] as int,
          avatarRegenCost: json['avatar_regen_cost'] as int,
          nicknameChangeableAt: changeableAt == null ? null : DateTime.parse(changeableAt).toLocal(),
        );
      });

  static MyPhoto _photo(Map<String, dynamic> json) => MyPhoto(
        id: json['id'] as String,
        url: json['url'] as String,
        isAvatarSource: json['is_avatar_source'] as bool,
      );

  @override
  Future<Result<void>> updateProfile({String? bio, String? nickname, int? heightCm}) => _api.send(
        'PATCH',
        '/me/profile',
        (_) {},
        body: {'bio': ?bio, 'nickname': ?nickname, 'height_cm': ?heightCm},
      );
}
