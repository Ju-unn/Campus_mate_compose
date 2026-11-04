import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/ideal_conditions_submission.dart';

abstract interface class IdealConditionsRepository {
  Future<Result<void>> submit(IdealConditionsSubmission submission);
}
