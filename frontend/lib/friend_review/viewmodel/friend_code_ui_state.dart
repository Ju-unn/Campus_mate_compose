import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/referral/viewmodel/referral_code_ui_state.dart';

/// 20f 화면이 그리는 상태 하나(pen 프레임 이름 그대로). [failed] 는 pen 에 없다(네트워크 등 — 대장 확인 대기).
enum FriendCodePhase {
  /// 20f-1 `eShpy` 입력 전 · 고치는 중.
  input,

  /// 확인을 보냈다(pen 에 없음 — 버튼 안 도는 표시).
  checking,

  /// 20f-2 `a6jyqI` 404.
  notFound,

  /// 20f-4 `Mi3ux` 429.
  tryLater,

  /// 그 밖의 실패. 문구는 [FriendCodeUiState.failureMessage].
  failed,

  /// 20f-3 `Q3xfwm` 확인 성공.
  found,

  /// 20f-3b `uovMC` 이미 쓴 친구.
  alreadyReviewed,
}

/// 20f 친구 코드로 리뷰 쓰기 화면 하나의 상태.
class FriendCodeUiState {
  const FriendCodeUiState({this.code = '', this.phase = FriendCodePhase.input, this.friend, this.failureMessage});

  /// 입력칸 글자 — 포매터가 대문자 · 영숫자만 남겼다.
  final String code;
  final FriendCodePhase phase;

  /// [FriendCodePhase.found] · [FriendCodePhase.alreadyReviewed] 일 때만 있다.
  final FriendCodeMatch? friend;

  /// [FriendCodePhase.failed] 문구.
  final String? failureMessage;

  /// "확인" 을 누를 수 있나 — 코드가 6자일 때만(20 화면과 같다). 20f-4 는 코드를 고치기 전까지 꺼 둔다(pen Mi3ux 버튼 #E5E5E5).
  bool get canCheck =>
      code.length == referralCodeLength &&
      (phase == FriendCodePhase.input || phase == FriendCodePhase.notFound || phase == FriendCodePhase.failed);

  /// "리뷰 쓰기" 를 누를 수 있나(20f-3 만 — 20f-3b 는 꺼짐).
  bool get canWrite => phase == FriendCodePhase.found;
}
