import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository.dart';

/// ViewModel · 화면 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeFriendReviewRepository implements FriendReviewRepository {
  Result<List<FriendReview>> about = const Success([]);
  Result<List<FriendReview>> received = const Success([]);
  Result<ReviewTarget> target = Success(reviewTargetFixture());
  Result<void> createResult = const Success(null);
  Result<List<FriendReview>> written = const Success([]);
  Result<void> deleteResult = const Success(null);

  final List<String> aboutRequests = [];
  int receivedCount = 0;
  int writtenCount = 0;
  final List<String> deletes = [];
  final List<String> targetRequests = [];
  final List<({String revieweeId, List<String> tags, String? comment})> creates = [];

  /// 채워 두면 create() 가 이것이 끝날 때까지 멈춘다 — 진행 중에 한 번 더 누르는 상황용.
  Completer<void>? holdCreate;

  /// 채워 두면 fetchTarget() 이 이것이 끝날 때까지 멈춘다 — 20b 를 여는 중에 닫는 상황용.
  Completer<void>? holdTarget;

  /// 채워 두면 fetchReceived() 가 이것이 끝날 때까지 멈춘다 — 20c 목록을 읽는 중에 닫는 상황용.
  Completer<void>? holdReceived;

  /// 채워 두면 fetchWritten() 이 이것이 끝날 때까지 멈춘다 — 20e 목록을 읽는 중 상태용.
  Completer<void>? holdWritten;

  /// 채워 두면 delete() 가 이것이 끝날 때까지 멈춘다 — 지우는 중에 또 누르거나 시트를 닫는 상황용.
  Completer<void>? holdDelete;

  @override
  Future<Result<List<FriendReview>>> fetchWritten() async {
    writtenCount += 1;
    await holdWritten?.future;
    return written;
  }

  @override
  Future<Result<void>> delete(String reviewId) async {
    deletes.add(reviewId);
    await holdDelete?.future;
    return deleteResult;
  }

  @override
  Future<Result<List<FriendReview>>> fetchAbout(String profileId) async {
    aboutRequests.add(profileId);
    return about;
  }

  @override
  Future<Result<List<FriendReview>>> fetchReceived() async {
    receivedCount += 1;
    await holdReceived?.future;
    return received;
  }

  @override
  Future<Result<ReviewTarget>> fetchTarget(String profileId) async {
    targetRequests.add(profileId);
    await holdTarget?.future;
    return target;
  }

  @override
  Future<Result<void>> create({
    required String revieweeId,
    required List<String> tags,
    String? comment,
  }) async {
    creates.add((revieweeId: revieweeId, tags: tags, comment: comment));
    await holdCreate?.future;
    return createResult;
  }
}

ReviewTarget reviewTargetFixture({
  String profileId = 'p2',
  String nickname = '달빛',
  String? avatarUrl,
}) {
  return ReviewTarget(profileId: profileId, nickname: nickname, avatarUrl: avatarUrl);
}

FriendReview friendReviewFixture({
  String id = 'r1',
  String nickname = '달빛',
  String? avatarUrl,
  String? university = '테스트대학교',
  List<String> tags = const ['성실해요'],
  String? comment,
  DateTime? createdAt,
}) {
  return FriendReview(
    id: id,
    nickname: nickname,
    avatarUrl: avatarUrl,
    university: university,
    tags: tags,
    comment: comment,
    createdAt: createdAt ?? DateTime.utc(2026, 9, 28, 5),
  );
}
