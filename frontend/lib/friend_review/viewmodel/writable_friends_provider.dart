import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 20e 위 "리뷰를 기다리는 친구"(pen `J3d8g8`). 실패도 [Result] 그대로 — 던지면 Riverpod 3 재시도 타이머를 건다.
/// autoDispose: 20e 를 나가면 내려가고, 다시 들어오면 새로 읽는다.
final writableFriendsProvider = FutureProvider.autoDispose<Result<List<ReviewTarget>>>((ref) {
  return ref.watch(friendReviewRepositoryProvider).fetchWritable();
});
