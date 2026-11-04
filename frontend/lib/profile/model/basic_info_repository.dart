import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/basic_info_submission.dart';

abstract interface class BasicInfoRepository {
  Future<Result<bool>> checkNicknameAvailability(String nickname);
  Future<Result<void>> submit(BasicInfoSubmission submission);
}
