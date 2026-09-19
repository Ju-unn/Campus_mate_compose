import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/sign_up_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignUpUiState.canSubmit', () {
    test('이메일이 없으면 제출할 수 없다', () {
      const state = SignUpUiState();

      expect(state.canSubmit, isFalse);
    });

    test('이메일이 있으면 제출할 수 있다', () {
      final state = SignUpUiState(
        emailInput: 'hong@snu.ac.kr',
        email: UniversityEmail.tryParse('hong@snu.ac.kr'),
      );

      expect(state.canSubmit, isTrue);
    });

    test('제출 중이면 canSubmit 이 false', () {
      final state = SignUpUiState(email: UniversityEmail.tryParse('hong@snu.ac.kr'), isSubmitting: true);
      expect(state.canSubmit, isFalse);
    });
  });

  test('기본값은 제출 중이 아니고 에러도 없다', () {
    const state = SignUpUiState();
    expect(state.isSubmitting, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.otpSentTo, isNull);
  });
}
