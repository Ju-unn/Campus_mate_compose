import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';

abstract interface class SurveyRepository {
  Future<Result<void>> submit(Map<int, double> answers, Religion religion, bool isSmoker);
}
