import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/auth/viewmodel/school_info_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final department = Department.tryParse('컴퓨터공학과')!;
  final studentNumber = StudentNumber.tryParse('20240001')!;

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
