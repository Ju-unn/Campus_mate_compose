import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository.dart';

class FakeAvatarRepository implements AvatarRepository {
  Result<AvatarGenerationOutcome> nextResult = const Success(AvatarReady('path.png'));
  int generateCount = 0;

  @override
  Future<Result<AvatarGenerationOutcome>> generateAvatar() async {
    generateCount++;
    return nextResult;
  }
}
