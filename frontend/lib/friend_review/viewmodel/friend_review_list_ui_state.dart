import 'package:campus_mate/friend_review/model/friend_review.dart';

/// 20c 받은 리뷰 · 20e 내가 쓴 리뷰 · 14c/14d 매칭 상대 리뷰 목록 하나의 상태. 읽기 한 번으로 끝나는 화면이라
/// 결과마다 새로 만들고 copyWith 는 두지 않는다(PartnerProfileUiState 와 같은 자리).
class FriendReviewListUiState {
  const FriendReviewListUiState({
    this.isLoading = true,
    this.reviews = const [],
    this.errorMessage,
  });

  final bool isLoading;
  final List<FriendReview> reviews;
  final String? errorMessage;
}
