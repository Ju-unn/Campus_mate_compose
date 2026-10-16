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

  /// 보낸 횟수 — 두 번 눌러도 한 번만 가는지 본다.
  int submitCount = 0;

  /// 채워 두면 보내기가 여기서 멈춘다 — "보내는 중" 화면을 테스트가 볼 때만 쓴다.
  Completer<void>? submitGate;

  @override
  Future<Result<void>> submit(BasicInfoSubmission submission) async {
    submitCount++;
    submitted = submission;
    await submitGate?.future;
    return nextSubmitResult;
  }
}
