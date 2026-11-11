import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/basic/model/data/basic_info_submission.dart';
import 'package:campus_mate/profile/basic/model/data/phone_code_sent.dart';

abstract interface class BasicInfoRepository {
  Future<Result<bool>> checkNicknameAvailability(String nickname);
  Future<Result<void>> submit(BasicInfoSubmission submission);

  /// 휴대폰 인증번호 문자를 보낸다. [phoneDigits] 는 하이픈 없는 숫자다.
  Future<Result<PhoneCodeSent>> sendPhoneCode(String phoneDigits);

  /// 받은 6자리 인증번호를 확인한다. 성공하면 서버가 그 번호를 30분 동안 저장해도 되는 번호로 기억한다.
  Future<Result<void>> verifyPhoneCode(String phoneDigits, String code);
}
