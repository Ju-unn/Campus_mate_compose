import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/acquisition_repository.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// [AcquisitionRepository]를 FastAPI 호출로 구현한다(POST /profile-onboarding/acquisition).
class HttpAcquisitionRepository implements AcquisitionRepository {
  const HttpAcquisitionRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit(AcquisitionChannel channel, String? note) => _api.send(
        'POST',
        '/profile-onboarding/acquisition',
        (_) {},
        body: {'channel': channel.name, 'note': note},
      );
}
