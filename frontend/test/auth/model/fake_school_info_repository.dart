import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/school_info_repository.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [SchoolInfoRepository]. 기본은 제출 성공이고,
/// `nextSubmitResult` 를 지정해 실패를 흉내 낼 수 있다.
class FakeSchoolInfoRepository implements SchoolInfoRepository {
  Result<void> nextSubmitResult = const Success(null);

  /// 지정하면 `submit()` 이 `Result` 대신 이 값을 던진다.
  /// 세션 만료·비정상 응답 바디처럼 `Result` 밖으로 새는 예외 경로를 흉내 내기 위함.
  Object? nextSubmitError;

  /// 서버로 실제 제출이 갔는지 확인하는 용도.
  final List<Department> submittedDepartments = [];
  final List<StudentNumber> submittedStudentNumbers = [];

  @override
  Future<Result<void>> submit(Department department, StudentNumber studentNumber) {
    submittedDepartments.add(department);
    submittedStudentNumbers.add(studentNumber);
    final error = nextSubmitError;
    if (error != null) {
      return Future.delayed(Duration.zero, () => throw error);
    }
    return Future.delayed(Duration.zero, () => nextSubmitResult);
  }
}
