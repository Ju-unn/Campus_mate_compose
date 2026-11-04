import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/graduate/model/data/verification_method.dart';

/// 인증 방법 고르기의 상태. 카드를 누르는 것은 앱 안 선택([selected])일 뿐 서버에 쓰지 않는다.
class VerificationMethodUiState {
  const VerificationMethodUiState({this.selected, this.isSubmitting = false, this.error});

  final VerificationMethod? selected;
  final bool isSubmitting;

  /// 실패의 종류. 화면이 글자로 바꿔 토스트로 한 번 띄운다. 동작 하나가 끝날 때마다 새 상태를 만들므로 그 한 번에만 붙는다.
  final Failure? error;

  /// [다음] 을 누를 수 있다 — 고른 카드가 있고 보내는 중이 아니다.
  bool get canGoNext => selected != null && !isSubmitting;
}
