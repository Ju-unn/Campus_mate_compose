import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/bio_repository.dart';

/// [BioRepository]를 FastAPI 호출로 구현한다.
class HttpBioRepository implements BioRepository {
  const HttpBioRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<String>> generateDraft() => _api.send(
        'POST',
        '/profile-onboarding/bio-draft',
        (body) => (body as Map<String, dynamic>)['draft'] as String,
      );

  @override
  Future<Result<void>> submit(String bio) =>
      _api.send('POST', '/profile-onboarding/bio', (_) {}, body: {'bio': bio});
}
