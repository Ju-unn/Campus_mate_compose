import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository.dart';
import 'package:campus_mate/friend_review/model/http_friend_review_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 20b 작성 시트 · 20c 목록 · 14c/14d 카드가 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final friendReviewRepositoryProvider = Provider<FriendReviewRepository>((ref) {
  return HttpFriendReviewRepository(ref.read(apiClientProvider));
});
