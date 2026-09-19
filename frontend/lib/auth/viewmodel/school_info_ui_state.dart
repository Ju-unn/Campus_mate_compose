import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/student_number.dart';

/// 학과·학번 입력 화면(DESIGN.md 화면 3c)의 상태.
class SchoolInfoUiState {
  const SchoolInfoUiState({
    this.departmentInput = '',
    this.department,
    this.studentNumberInput = '',
    this.studentNumber,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  /// 입력창에 그대로 보여줄 원본 문자열.
  final String departmentInput;

  /// 형식이 올바를 때만 값이 있다. `null` 이면 CTA 를 누를 수 없다.
  final Department? department;

  /// 입력창에 그대로 보여줄 원본 문자열.
  final String studentNumberInput;

  /// 형식이 올바를 때만 값이 있다. `null` 이면 CTA 를 누를 수 없다.
  final StudentNumber? studentNumber;

  /// 제출이 서버 응답을 기다리는 중인지.
  final bool isSubmitting;

  /// 조회·제출이 실패했을 때 보여줄 문구.
  final String? errorMessage;

  /// 제출이 끝났는지 — 라우터가 이 값을 보고 인증 게이트를 다시 평가한다(Task A10).
  final bool completed;

  bool get canSubmit => department != null && studentNumber != null && !isSubmitting;
}
