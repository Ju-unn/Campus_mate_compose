import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository.dart';

/// [AvatarRepository]를 FastAPI 호출로 구현한다.
class HttpAvatarRepository implements AvatarRepository {
  const HttpAvatarRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<AvatarGenerationOutcome>> generateAvatar() =>
      _api.send('POST', '/profile-onboarding/avatar/generate', _toOutcome);

  AvatarGenerationOutcome _toOutcome(Object body) {
    final fields = body as Map<String, dynamic>;
    return switch (fields['status'] as String) {
      'ready' => AvatarReady(fields['storage_path'] as String),
      'fallback' => AvatarFallback(fields['compensation_hearts'] as int),
      _ => const AvatarFailed(),
    };
  }
}
