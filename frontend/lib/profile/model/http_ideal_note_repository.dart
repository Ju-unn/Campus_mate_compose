import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/ideal_note_repository.dart';

/// [IdealNoteRepository]를 FastAPI 호출로 구현한다.
class HttpIdealNoteRepository implements IdealNoteRepository {
  const HttpIdealNoteRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit(String note) =>
      _api.send('POST', '/profile-onboarding/ideal-note', (_) {}, body: {'note': note});
}
