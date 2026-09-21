import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/school_info_repository.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [SchoolInfoRepository]를 FastAPI 호출로 구현한다.
class HttpSchoolInfoRepository implements SchoolInfoRepository {
  const HttpSchoolInfoRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit(Department department, StudentNumber studentNumber) => _api.send(
        'POST',
        '/school-info',
        (_) {},
        body: {
          'department': department.toRequestValue(),
          'student_number': studentNumber.toRequestValue(),
        },
      );
}
