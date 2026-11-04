import 'package:campus_mate/auth/school_info/model/data/department.dart';
import 'package:campus_mate/auth/school_info/model/data/student_number.dart';
import 'package:campus_mate/common/result.dart';

abstract interface class SchoolInfoRepository {
  Future<Result<void>> submit(Department department, StudentNumber studentNumber);
}
