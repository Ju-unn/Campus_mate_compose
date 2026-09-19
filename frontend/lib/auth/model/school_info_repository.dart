import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/common/result.dart';

abstract interface class SchoolInfoRepository {
  Future<Result<void>> submit(Department department, StudentNumber studentNumber);
}
