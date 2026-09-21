import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/basic_info_repository.dart';

/// [BasicInfoRepository]를 FastAPI 호출로 구현한다.
class HttpBasicInfoRepository implements BasicInfoRepository {
  const HttpBasicInfoRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<bool>> checkNicknameAvailability(String nickname) => _api.send(
        'GET',
        '/profile-onboarding/nickname-availability',
        (body) => (body as Map<String, dynamic>)['available'] as bool,
        query: {'nickname': nickname},
      );

  @override
  Future<Result<void>> submit(BasicInfoSubmission submission) => _api.send(
        'POST',
        '/profile-onboarding/basic-info',
        (_) {},
        body: {
          'nickname': submission.nickname,
          'birth_year': submission.birthYear,
          'height_cm': submission.heightCm,
          'phone_number': submission.phoneNumber,
          'gender': submission.gender,
          'mbti': submission.mbti,
        },
      );
}
