import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository.dart';

class FakeIdealConditionsRepository implements IdealConditionsRepository {
  Result<void> nextResult = const Success(null);
  IdealConditionsSubmission? submitted;

  /// 채워 두면 저장이 이 Completer 가 끝날 때까지 기다린다("저장 중" 모양 확인용).
  Completer<void>? hold;

  @override
  Future<Result<void>> submit(IdealConditionsSubmission submission) async {
    submitted = submission;
    await hold?.future;
    return nextResult;
  }
}
