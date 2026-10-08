import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/viewmodel/start_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StartUiState', () {
    test('아무것도 진행 중이 아니면 모든 버튼을 누를 수 있고 스피너는 없다', () {
      const state = StartUiState();

      for (final provider in SocialProvider.values) {
        expect(state.isEnabled(provider), isTrue, reason: '$provider');
        expect(state.isLoading(provider), isFalse, reason: '$provider');
      }
    });

    test('하나가 진행 중이면 그 버튼만 스피너, 모든 버튼은 누를 수 없다', () {
      const state = StartUiState(inProgress: SocialProvider.google);

      expect(state.isLoading(SocialProvider.google), isTrue);
      expect(state.isLoading(SocialProvider.kakao), isFalse);
      expect(SocialProvider.values.where(state.isEnabled), isEmpty);
    });
  });

  group('StartToast', () {
    test('취소는 취소 모양(내용 폭 · info), 실패는 실패 모양(버튼 폭 · 경고)으로 문구를 보인다', () {
      final cancelled = StartToast.fromFailure(const LoginCancelledFailure());
      final failed = StartToast.fromFailure(const SocialLoginFailure());

      expect((cancelled.message, cancelled.isCancellation), ('로그인이 취소됐어요', true));
      expect((failed.message, failed.isCancellation), ('로그인하지 못했어요. 잠시 뒤 다시 시도해 주세요', false));
    });
  });
}
