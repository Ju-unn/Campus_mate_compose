import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/appearance_type_repository.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// [AppearanceTypeRepository]를 FastAPI 호출로 구현한다.
class HttpAppearanceTypeRepository implements AppearanceTypeRepository {
  const HttpAppearanceTypeRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit(AnimalType animalType, ImpressionType impressionType) => _api.send(
        'POST',
        '/profile-onboarding/appearance-type',
        (_) {},
        body: {'animal_type': animalType.name, 'impression_type': impressionType.name},
      );
}
