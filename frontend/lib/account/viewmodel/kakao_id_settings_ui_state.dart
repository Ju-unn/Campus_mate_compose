import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/input_rules.dart';

/// 16e-1 카카오톡 아이디 변경(pen `bWrnD`)의 상태.
class KakaoIdSettingsUiState {
  const KakaoIdSettingsUiState({
    this.kakaoIdInput = '',
    this.savedKakaoId = '',
    this.kakaoIdChecked = false,
    this.isLoading = true,
    this.isSubmitting = false,
    this.error,
    this.completed = false,
  });

  final String kakaoIdInput;

  /// 서버에서 읽은 아이디. 옛 앱이 받은 값일 수 있어 고치지 않은 동안은 미리 검사하지 않는다(대장 규칙, 15-6 과 같다).
  final String savedKakaoId;

  /// 쓰다 손을 멈췄다(300ms 디바운스) — 04-1b 와 같다.
  final bool kakaoIdChecked;

  /// 사용자가 읽어 온 값을 고쳤다 — 이때만 미리 검사한다. 서버는 저장할 때 언제나 다시 본다.
  bool get _isEdited => kakaoIdInput != savedKakaoId;

  /// 저장된 아이디를 읽는 중. 읽기 전에 저장하면 빈 칸이 덮어쓴다.
  final bool isLoading;
  final bool isSubmitting;
  final Failure? error;

  /// 저장까지 끝났다 — 화면이 true 를 들고 닫힌다.
  final bool completed;

  /// 칸 아래 빨간 한 줄 — 04-1b(KakaoIdUiState.fieldError)와 같다.
  Failure? get fieldError => error ?? (_isEdited ? kakaoIdFieldError(kakaoIdInput, settled: kakaoIdChecked) : null);

  /// 고친 값은 04-1b(KakaoIdUiState)와 같은 규칙(서버 `is_valid_kakao_id`), 고치지 않은 옛 값은 비어 있지만 않으면 된다.
  /// 읽는 중에도 못 보낸다.
  bool get canSubmit =>
      !isLoading && !isSubmitting && (_isEdited ? isValidKakaoId(kakaoIdInput) : kakaoIdInput.trim().isNotEmpty);
}
