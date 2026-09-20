import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository.dart';

class FakeIdealConditionsRepository implements IdealConditionsRepository {
  Result<void> nextResult = const Success(null);
  IdealConditionsSubmission? submitted;

  @override
  Future<Result<void>> submit(IdealConditionsSubmission submission) async {
    submitted = submission;
    return nextResult;
  }
}
