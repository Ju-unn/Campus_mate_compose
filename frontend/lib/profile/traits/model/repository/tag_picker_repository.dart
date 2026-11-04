import 'package:campus_mate/common/result.dart';

abstract interface class TagPickerRepository {
  Future<Result<void>> submit(String endpoint, List<String> tags);
}
