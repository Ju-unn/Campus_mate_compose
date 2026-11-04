import 'package:campus_mate/auth/social/viewmodel/reviewer_login_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('처음에는 진행 중도 실패도 닫힘 신호도 없다', () {
    const state = ReviewerLoginUiState();

    expect((state.isSubmitting, state.failure, state.completed), (false, null, false));
  });

  group('isFilled — 두 칸이 모두 찼는지(가짜 값)', () {
    test('이메일과 비밀번호가 있으면 true', () {
      expect(ReviewerLoginUiState.isFilled('reviewer@example.test', 'fake-password-1'), isTrue);
    });

    test('이메일이 비었거나 공백뿐이면 false', () {
      expect(ReviewerLoginUiState.isFilled('', 'fake-password-1'), isFalse);
      expect(ReviewerLoginUiState.isFilled('   ', 'fake-password-1'), isFalse);
    });

    test('비밀번호가 비었으면 false — 비밀번호는 공백도 글자로 센다', () {
      expect(ReviewerLoginUiState.isFilled('reviewer@example.test', ''), isFalse);
      expect(ReviewerLoginUiState.isFilled('reviewer@example.test', ' '), isTrue);
    });
  });

  test('실패 종류를 그대로 들고 있다 — 글자는 view 가 context.errorText 로 만든다', () {
    const state = ReviewerLoginUiState(failure: RateLimitedFailure());

    expect(state.failure, isA<RateLimitedFailure>());
  });
}
