import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/school_info_repository.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [SchoolInfoRepository]. 기본은 제출 성공이고,
/// `nextSubmitResult` 를 지정해 실패를 흉내 낼 수 있다.
class FakeSchoolInfoRepository implements SchoolInfoRepository {
  Result<void> nextSubmitResult = const Success(null);

  /// 서버로 실제 제출이 갔는지 확인하는 용도.
  final List<Department> submittedDepartments = [];
  final List<StudentNumber> submittedStudentNumbers = [];

  @override
  Future<Result<void>> submit(Department department, StudentNumber studentNumber) {
    submittedDepartments.add(department);
    submittedStudentNumbers.add(studentNumber);
    return Future.delayed(Duration.zero, () => nextSubmitResult);
  }
}
