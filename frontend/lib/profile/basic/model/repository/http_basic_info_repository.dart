import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/basic/model/data/basic_info_submission.dart';
import 'package:campus_mate/profile/basic/model/data/phone_code_sent.dart';
import 'package:campus_mate/profile/basic/model/repository/basic_info_repository.dart';

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

  /// 번호는 기본 정보 저장과 같이 숫자만 보낸다 — 서버(`to_signup_e164`)가 하이픈을 떼고 같은 번호로 읽는다.
  @override
  Future<Result<PhoneCodeSent>> sendPhoneCode(String phoneDigits) => _api.send(
        'POST',
        '/phone-verification/send',
        (body) {
          final json = body as Map<String, dynamic>;
          return PhoneCodeSent(
            resendAfter: Duration(seconds: json['resend_after_seconds'] as int),
            expiresIn: Duration(seconds: json['expires_in_seconds'] as int),
            alreadySent: json['already_sent'] as bool,
          );
        },
        body: {'phone_number': phoneDigits},
      );

  @override
  Future<Result<void>> verifyPhoneCode(String phoneDigits, String code) => _api.send(
        'POST',
        '/phone-verification/verify',
        (_) {},
        body: {'phone_number': phoneDigits, 'code': code},
      );
}
