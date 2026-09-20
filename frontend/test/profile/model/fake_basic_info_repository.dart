import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/basic_info_repository.dart';

class FakeBasicInfoRepository implements BasicInfoRepository {
  Result<bool> nextAvailabilityResult = const Success(true);
  Result<void> nextSubmitResult = const Success(null);
  final List<String> checkedNicknames = [];
  BasicInfoSubmission? submitted;

  @override
  Future<Result<bool>> checkNicknameAvailability(String nickname) async {
    checkedNicknames.add(nickname);
    return nextAvailabilityResult;
  }

  @override
  Future<Result<void>> submit(BasicInfoSubmission submission) async {
    submitted = submission;
    return nextSubmitResult;
  }
}
