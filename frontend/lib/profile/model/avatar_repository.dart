import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';

abstract interface class AvatarRepository {
  Future<Result<AvatarGenerationOutcome>> generateAvatar();
}
