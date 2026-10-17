import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/model/survey_repository.dart';

class FakeSurveyRepository implements SurveyRepository {
  Result<void> nextResult = const Success(null);
  Map<int, double>? submittedAnswers;
  Religion? submittedReligion;
  bool? submittedIsSmoker;

  /// 채워 두면 저장이 이 Completer 가 끝날 때까지 기다린다("저장 중" 확인용).
  Completer<void>? hold;

  @override
  Future<Result<void>> submit(Map<int, double> answers, Religion religion, bool isSmoker) async {
    submittedAnswers = answers;
    submittedReligion = religion;
    submittedIsSmoker = isSmoker;
    await hold?.future;
    return nextResult;
  }
}
