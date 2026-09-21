import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/tag_picker_repository.dart';

/// [TagPickerRepository]를 FastAPI 호출로 구현한다.
class HttpTagPickerRepository implements TagPickerRepository {
  const HttpTagPickerRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit(String endpoint, List<String> tags) =>
      _api.send('POST', '/profile-onboarding/$endpoint', (_) {}, body: {'tags': tags});
}
