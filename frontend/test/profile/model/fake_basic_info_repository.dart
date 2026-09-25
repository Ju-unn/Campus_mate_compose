import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/basic_info_repository.dart';

class FakeBasicInfoRepository implements BasicInfoRepository {
  Result<bool> nextAvailabilityResult = const Success(true);
  Result<void> nextSubmitResult = const Success(null);
  final List<String> checkedNicknames = [];
  BasicInfoSubmission? submitted;

  /// 채워 두면 조회가 여기서 멈춘다 — "조회 중에 입력이 또 바뀌는" 상황을 테스트가 만들 때만 쓴다.
  Completer<void>? availabilityGate;

  @override
  Future<Result<bool>> checkNicknameAvailability(String nickname) async {
    checkedNicknames.add(nickname);
    await availabilityGate?.future;
    return nextAvailabilityResult;
  }

  @override
  Future<Result<void>> submit(BasicInfoSubmission submission) async {
    submitted = submission;
    return nextSubmitResult;
  }
}
