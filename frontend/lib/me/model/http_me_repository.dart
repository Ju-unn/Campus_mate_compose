import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/me/model/me_repository.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:http/http.dart' as http;

/// [MeRepository] 를 FastAPI `GET · PATCH /me/profile` · `GET /me/card-preview` · `PUT /me/photos` 로 구현한다.
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
          religion: _enumOrNull(Religion.values, json['religion']),
          isSmoker: json['is_smoker'] as bool?,
          animalType: _enumOrNull(AnimalType.values, json['animal_type']),
          impressionType: _enumOrNull(ImpressionType.values, json['impression_type']),
          birthYear: json['birth_year'] as int?,
          gender: json['gender'] as String?,
        );
      });

  /// 서버 문자열(= enum 이름)을 열거형으로. null 이거나 키가 없으면 null, 모르는 값이면 던진다(→ 실패 처리).
  static T? _enumOrNull<T extends Enum>(List<T> values, Object? name) => name == null ? null : values.byName(name as String);

  static MyPhoto _photo(Map<String, dynamic> json) => MyPhoto(
        id: json['id'] as String,
        url: json['url'] as String,
        isAvatarSource: json['is_avatar_source'] as bool,
      );

  /// 10b 카드 상세와 같은 몸통이라 모델을 다시 만들지 않는다 — card_id 자리에는 내 profile_id 를 넣는다
  /// (14c 가 match_id 를 넣는 것과 같은 모양, `partner_profile.dart`).
  @override
  Future<Result<CardDetail>> fetchCardPreview() => _api.send('GET', '/me/card-preview', (body) {
        final json = body as Map<String, dynamic>;
        final profile = json['profile'] as Map<String, dynamic>;
        return CardDetail.fromJson({...json, 'card_id': profile['profile_id']});
      });

  @override
  Future<Result<void>> updateProfile({
    String? bio,
    String? nickname,
    int? heightCm,
    String? mbti,
    bool clearMbti = false,
    Religion? religion,
    bool? isSmoker,
    ({AnimalType animalType, ImpressionType impressionType})? appearance,
  }) {
    assert(mbti == null || !clearMbti, 'MBTI 는 글자를 보내거나 지우거나 둘 중 하나다');
    return _api.send(
      'PATCH',
      '/me/profile',
      (_) {},
      body: {
        'bio': ?bio,
        'nickname': ?nickname,
        'height_cm': ?heightCm,
        // MBTI 만 null 이 "선택 안 함" 이라는 뜻이다 — 서버가 모든 null 을 거절하는 다른 칸과 달리 이 칸만 null 을 보낸다.
        if (clearMbti) 'mbti': null else 'mbti': ?mbti,
        'religion': ?religion?.name,
        'is_smoker': ?isSmoker,
        'animal_type': ?appearance?.animalType.name,
        'impression_type': ?appearance?.impressionType.name,
      },
    );
  }

  /// `ApiClient.sendMultipart` 는 파일 하나 · POST 전용이라 `sendRequest` 로 직접 만든다.
  @override
  Future<Result<void>> savePhotos(List<PhotoSlot> slots, int avatarSource) async {
    final files = [for (final slot in slots) if (slot is NewPhoto) slot.file];
    var next = 0;
    // 새 파일 번호는 칸 순서대로 매긴다 — 서버는 번호가 파일 순서와 맞는지 본다(parse_layout).
    final layout = [
      for (final slot in slots)
        switch (slot) {
          KeptPhoto(:final id) => {'keep': id},
          NewPhoto() => {'new': next++},
        },
    ];
    final result = await _api.sendRequest((accessToken) async {
      final request = http.MultipartRequest('PUT', _api.uri('/me/photos'))
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..fields['layout'] = jsonEncode(layout)
        ..fields['avatar_source'] = avatarSource.toString();
      for (final file in files) {
        request.files.add(await http.MultipartFile.fromPath('photos', file.path));
      }
      return request;
    });
    return result.when(onSuccess: (_) => const Success(null), onFailure: FailureResult.new);
  }
}
