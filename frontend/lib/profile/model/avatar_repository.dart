import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';

abstract interface class AvatarRepository {
  /// 작업을 **등록만** 한다(202). 그림이 완성될 때까지 기다리지 않는다.
  Future<Result<AvatarGenerationOutcome>> generateAvatar();

  /// 지금 어디까지 왔는지 묻는다. 결과 화면이 만드는 동안 되풀이해 부른다.
  Future<Result<AvatarGenerationOutcome>> fetchAvatarStatus();
}
