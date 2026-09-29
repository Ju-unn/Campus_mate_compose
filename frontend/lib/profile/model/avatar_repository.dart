import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';

abstract interface class AvatarRepository {
  /// 작업을 **등록만** 한다(202). 그림이 완성될 때까지 기다리지 않는다.
  Future<Result<AvatarGenerationOutcome>> generateAvatar();

  /// 지금 어디까지 왔는지 묻는다. 결과 화면이 만드는 동안 되풀이해 부른다.
  Future<Result<AvatarGenerationOutcome>> fetchAvatarStatus();

  /// 화면 15 "다시 만들기"(15b). [generateAvatar] 처럼 **등록만** 한다 — 결과는 [fetchAvatarStatus] 로 묻는다.
  /// 하트는 여기서 빠지지 않는다. 서버가 그림이 완성된 뒤에만 뺀다.
  Future<Result<AvatarGenerationOutcome>> regenerateAvatar();
}
