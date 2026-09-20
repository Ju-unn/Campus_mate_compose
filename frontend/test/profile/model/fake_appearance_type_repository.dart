import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/appearance_type_repository.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

class FakeAppearanceTypeRepository implements AppearanceTypeRepository {
  Result<void> nextResult = const Success(null);
  AnimalType? submittedAnimalType;
  ImpressionType? submittedImpressionType;

  @override
  Future<Result<void>> submit(AnimalType animalType, ImpressionType impressionType) async {
    submittedAnimalType = animalType;
    submittedImpressionType = impressionType;
    return nextResult;
  }
}
