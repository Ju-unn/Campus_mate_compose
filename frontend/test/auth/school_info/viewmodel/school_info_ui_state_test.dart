import 'package:campus_mate/auth/school_info/model/data/department.dart';
import 'package:campus_mate/auth/school_info/model/data/student_number.dart';
import 'package:campus_mate/auth/school_info/viewmodel/school_info_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final department = Department.tryParse('컴퓨터공학과')!;
  final studentNumber = StudentNumber.tryParse('21')!;

  // 15-6 과 같은 안내(AppError.studentNumberInvalid). 빈 칸은 아직 안 친 것이라 안내하지 않는다.
  test('학번 칸이 비어 있지 않은데 2자리 숫자가 아니면 안내 오류, 비었거나 2자리면 없다', () {
    for (final input in ['1', '123', 'ab', '2023123']) {
      expect(
        SchoolInfoUiState(studentNumberInput: input).studentNumberError,
        isA<AppErrorFailure>().having((failure) => failure.error, 'error', AppError.studentNumberInvalid),
        reason: input,
      );
    }
    expect(const SchoolInfoUiState().studentNumberError, isNull);
    expect(SchoolInfoUiState(studentNumberInput: '21', studentNumber: studentNumber).studentNumberError, isNull);
  });

  test('기본 상태는 아직 아무 값도 없고 완료 전이다', () {
    const state = SchoolInfoUiState();

    expect(state.department, isNull);
    expect(state.studentNumber, isNull);
    expect(state.completed, isFalse);
    expect(state.canSubmit, isFalse);
  });

  test('학과와 학번이 모두 있고 제출 중이 아니면 제출할 수 있다', () {
    final state = SchoolInfoUiState(department: department, studentNumber: studentNumber);

    expect(state.canSubmit, isTrue);
  });

  test('학과가 없으면 제출할 수 없다', () {
    final state = SchoolInfoUiState(studentNumber: studentNumber);

    expect(state.canSubmit, isFalse);
  });

  test('학번이 없으면 제출할 수 없다', () {
    final state = SchoolInfoUiState(department: department);

    expect(state.canSubmit, isFalse);
  });

  test('이미 제출 중이면 다시 제출할 수 없다', () {
    final state = SchoolInfoUiState(
      department: department,
      studentNumber: studentNumber,
      isSubmitting: true,
    );

    expect(state.canSubmit, isFalse);
  });
}
