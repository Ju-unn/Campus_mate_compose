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

  @override
  Future<Result<AvatarGenerationOutcome>> fetchAvatarStatus() =>
      _api.send('GET', '/profile-onboarding/avatar/status', _toOutcome);

  /// 두 엔드포인트가 같은 모양으로 답하므로 파서도 하나다 — 한쪽만 고치면 그 길에서만 터진다.
  AvatarGenerationOutcome _toOutcome(Object body) {
    final fields = body as Map<String, dynamic>;
    return switch (fields['status'] as String) {
      'pending' => const AvatarPending(),
      // 저장 경로가 아니라 **전체 주소**다 — 서버가 버킷 접두사까지 붙여서 준다.
      'ready' => AvatarReady(fields['avatar_url'] as String),
      'fallback' => AvatarFallback(fields['avatar_url'] as String, fields['compensation_hearts'] as int),
      // 'failed' 와 'none' 을 같게 다룬다 — 여기서 작업을 자동 등록하지 않는다(서버도 안 한다).
      _ => const AvatarFailed(),
    };
  }
}
