import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';

/// 지인 리뷰(계획서 2026-09-28) 서버 호출.
abstract interface class FriendReviewRepository {
  /// 14c/14d 매칭 상대에게 쓴 리뷰들. 최신순.
  Future<Result<List<FriendReview>>> fetchAbout(String profileId);

  /// 20c 내가 받은 리뷰들. 최신순.
  Future<Result<List<FriendReview>>> fetchReceived();

  /// 20e 내가 쓴 리뷰들. 최신순. 카드 머리의 사람은 받은 사람(`reviewee`)이다.
  Future<Result<List<FriendReview>>> fetchWritten();

  /// 20e 내가 쓴 리뷰 하나를 지운다(204). 없으면 404 "리뷰를 찾을 수 없어요".
  Future<Result<void>> delete(String reviewId);

  /// 20b 를 열기 전에 물어보는 대상. 이미 썼으면 409(계획서 P3, 앱은 시트 대신 토스트).
  Future<Result<ReviewTarget>> fetchTarget(String profileId);

  /// [comment] 는 다듬어 비어 있으면 서버로 null 을 보낸다(HttpFriendReviewRepository 몫).
  Future<Result<void>> create({
    required String revieweeId,
    required List<String> tags,
    String? comment,
  });
}
