import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/model/survey_repository.dart';

class FakeSurveyRepository implements SurveyRepository {
  Result<void> nextResult = const Success(null);
  Map<int, double>? submittedAnswers;
  Religion? submittedReligion;
  bool? submittedIsSmoker;

  @override
  Future<Result<void>> submit(Map<int, double> answers, Religion religion, bool isSmoker) async {
    submittedAnswers = answers;
    submittedReligion = religion;
    submittedIsSmoker = isSmoker;
    return nextResult;
  }
}
