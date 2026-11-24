import 'package:campus_mate/auth/school_info/model/data/academic_status.dart';
import 'package:campus_mate/auth/school_info/model/data/department.dart';
import 'package:campus_mate/auth/school_info/model/data/student_number.dart';
import 'package:campus_mate/common/failure.dart';

/// 학과·학번 입력 화면(DESIGN.md 화면 3c)의 상태.
class SchoolInfoUiState {
  const SchoolInfoUiState({
    this.departmentInput = '',
    this.department,
    this.departmentChecked = false,
    this.studentNumberInput = '',
    this.studentNumber,
    this.academicStatus,
    this.isSubmitting = false,
    this.error,
    this.completed = false,
  });

  /// 입력창에 그대로 보여줄 원본 문자열.
  final String departmentInput;

  /// 형식이 올바를 때만 값이 있다. `null` 이면 CTA 를 누를 수 없다.
  final Department? department;

  /// 학과를 쓰다 손을 멈췄다(디바운스가 끝났다). 한글 입력기가 조합 중에 넣는 자모("경ㅇ")에 오류가 깜빡이지 않게 한다.
  final bool departmentChecked;

  /// 학과 칸 아래 빨간 한 줄 — 손을 멈춘 뒤, 쓴 값이 서버 규칙에 안 맞을 때만. 빈 칸에는 띄우지 않는다.
  /// 시안(I-1)에 문구가 없어 서버가 같은 값에 주는 글과 같은 종류를 쓴다(대장 판정 11-24, A안).
  Failure? get departmentError =>
      departmentChecked && departmentInput.isNotEmpty && department == null ? const AppErrorFailure(AppError.invalidInput) : null;

  /// 입력창에 그대로 보여줄 원본 문자열.
  final String studentNumberInput;

  /// 형식이 올바를 때만 값이 있다. `null` 이면 CTA 를 누를 수 없다.
  final StudentNumber? studentNumber;

  /// 신분(1.0.7 1-1, 필수). `null` 이면 아직 안 골라 CTA 를 누를 수 없다. 칩을 눌러도 저장은 [다음] 때 한 번이다.
  final AcademicStatus? academicStatus;

  /// 제출이 서버 응답을 기다리는 중인지.
  final bool isSubmitting;

  /// 조회·제출이 실패한 종류. 화면이 `context.errorText` 로 글자를 만들어 보인다.
  final Failure? error;

  /// 제출이 성공했는지 — ViewModel 이 이 값을 보고 인증 게이트를 다시 조회하고,
  /// 화면 전환은 라우터가 게이트 변화로 처리한다(Task A10).
  final bool completed;

  /// 학번 칸 아래 안내. 비었으면 아직 안 친 것이라 없고, 쳤는데 2자리 숫자가 아니면 15-6 과 같은 안내다.
  Failure? get studentNumberError => studentNumberInput.isNotEmpty && studentNumber == null
      ? const AppErrorFailure(AppError.studentNumberInvalid)
      : null;

  bool get canSubmit => department != null && studentNumber != null && academicStatus != null && !isSubmitting;
}
