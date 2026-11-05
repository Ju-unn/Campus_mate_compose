import 'package:campus_mate/common/failure.dart';

/// 투표 응답 뒤 화면이 토스트로 알릴 것. 하트를 받았거나([isReward]) 실패했다 — 글자는 view 가 문구 파일에서 읽는다.
class PollVoteNotice {
  /// 하루 첫 투표 보상을 받았다.
  const PollVoteNotice.reward() : failure = null;

  const PollVoteNotice.failed(Failure this.failure);

  /// 실패한 이유. 보상이면 null.
  final Failure? failure;

  bool get isReward => failure == null;
}
