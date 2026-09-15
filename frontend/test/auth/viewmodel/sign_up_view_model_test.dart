import 'package:campus_mate/auth/viewmodel/sign_up_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignUpViewModel', () {
    test('초기 상태는 빈 입력이고 제출할 수 없다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(signUpViewModelProvider);

      expect(state.emailInput, '');
      expect(state.canSubmit, isFalse);
    });

    test('형식이 올바른 이메일을 입력하면 제출할 수 있다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signUpViewModelProvider.notifier).changeEmail('hong@snu.ac.kr');
      final state = container.read(signUpViewModelProvider);

      expect(state.emailInput, 'hong@snu.ac.kr');
      expect(state.canSubmit, isTrue);
    });

    test('형식이 잘못된 이메일을 입력하면 제출할 수 없다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signUpViewModelProvider.notifier).changeEmail('hong@snu');
      final state = container.read(signUpViewModelProvider);

      expect(state.canSubmit, isFalse);
    });
  });
}
