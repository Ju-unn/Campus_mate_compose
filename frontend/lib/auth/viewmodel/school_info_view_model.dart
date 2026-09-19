import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/school_info_repository_provider.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/auth/viewmodel/school_info_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final schoolInfoViewModelProvider = NotifierProvider<SchoolInfoViewModel, SchoolInfoUiState>(
  SchoolInfoViewModel.new,
);

/// `_copyWith` 에서 "이 필드는 건드리지 않는다" 를 뜻하는 표식.
/// 넘기지 않은 것과 `null` 을 넘겨 값을 지우는 것을 구분하기 위해 필요하다
/// (학과·학번이 형식에 어긋나면 다시 `null` 로 지워야 한다).
const Object _keep = Object();

/// 학과·학번 입력 화면(DESIGN.md 화면 3c)의 흐름을 맡는다.
class SchoolInfoViewModel extends Notifier<SchoolInfoUiState> {
  @override
  SchoolInfoUiState build() {
    return const SchoolInfoUiState();
  }

  void changeDepartment(String value) {
    state = _copyWith(departmentInput: value, department: Department.tryParse(value));
  }

  void changeStudentNumber(String value) {
    state = _copyWith(studentNumberInput: value, studentNumber: StudentNumber.tryParse(value));
  }

  /// 학과·학번이 아직 없으면 아무 일도 하지 않는다.
  Future<void> submit() async {
    final department = state.department;
    final studentNumber = state.studentNumber;
    if (department == null || studentNumber == null) {
      return;
    }
    state = _copyWith(isSubmitting: true, errorMessage: null);
    state = await _submittedState(department, studentNumber);
  }

  /// 저장소 호출이 던지는 예외까지 흡수해 `isSubmitting` 이 영원히 true 로 굳지 않게 한다.
  /// (세션 만료·비정상 응답 바디로 `Result` 밖으로 새는 `TypeError` 등 — 해당 파일은 이 작업 범위 밖이라
  /// ViewModel 에서 막는다). `on Exception` 만으로는 `Error` 계열을 놓치므로 넓게 잡는다.
  Future<SchoolInfoUiState> _submittedState(Department department, StudentNumber studentNumber) async {
    try {
      final repository = ref.read(schoolInfoRepositoryProvider);
      final result = await repository.submit(department, studentNumber);
      return _stateFromResult(result);
    } catch (_) {
      return _copyWith(isSubmitting: false, errorMessage: const UnknownFailure().toDisplayMessage());
    }
  }

  /// 성공하면 `completed` 를 켜 라우터가 인증 게이트를 다시 평가하게 한다.
  SchoolInfoUiState _stateFromResult(Result<void> result) {
    return result.when(
      onSuccess: (_) => _copyWith(isSubmitting: false, completed: true),
      onFailure: (failure) => _copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 넘긴 필드만 바꾼 새 상태를 만든다.
  /// `department`·`studentNumber`·`errorMessage` 는 [_keep] 기본값이라
  /// `null` 을 넘기면 실제로 값이 지워진다.
  SchoolInfoUiState _copyWith({
    String? departmentInput,
    Object? department = _keep,
    String? studentNumberInput,
    Object? studentNumber = _keep,
    bool? isSubmitting,
    Object? errorMessage = _keep,
    bool? completed,
  }) {
    return SchoolInfoUiState(
      departmentInput: departmentInput ?? state.departmentInput,
      department: identical(department, _keep) ? state.department : department as Department?,
      studentNumberInput: studentNumberInput ?? state.studentNumberInput,
      studentNumber: identical(studentNumber, _keep) ? state.studentNumber : studentNumber as StudentNumber?,
      isSubmitting: isSubmitting ?? state.isSubmitting,
      errorMessage: identical(errorMessage, _keep) ? state.errorMessage : errorMessage as String?,
      completed: completed ?? state.completed,
    );
  }
}
