import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

abstract interface class AppearanceTypeRepository {
  Future<Result<void>> submit(AnimalType animalType, ImpressionType impressionType);
}
