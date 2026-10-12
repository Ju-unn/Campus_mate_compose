import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository.dart';

/// [FriendReviewRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류는
/// `sendAuthorizedRequest` 몫이라 여기서는 URL · 바디 · 파싱만 맡는다.
class HttpFriendReviewRepository implements FriendReviewRepository {
  const HttpFriendReviewRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<List<FriendReview>>> fetchAbout(String profileId) =>
      _api.send('GET', '/friend-reviews/about/$profileId', _parseReviews);

  @override
  Future<Result<List<FriendReview>>> fetchReceived() =>
      _api.send('GET', '/friend-reviews/received', _parseReviews);

  @override
  Future<Result<List<FriendReview>>> fetchWritten() =>
      _api.send('GET', '/friend-reviews/written', _parseReviews);

  /// 204 는 본문이 비어 있다 — `ApiClient.send` 가 빈 본문을 걸러 낸다.
  @override
  Future<Result<void>> delete(String reviewId) => _api.send('DELETE', '/friend-reviews/$reviewId', (_) {});

  @override
  Future<Result<List<ReviewTarget>>> fetchWritable() => _api.send(
        'GET',
        '/friend-reviews/writable',
        (body) => ((body as Map<String, dynamic>)['friends'] as List<dynamic>)
            .map((item) => ReviewTarget.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  List<FriendReview> _parseReviews(Object body) =>
      ((body as Map<String, dynamic>)['reviews'] as List<dynamic>)
          .map((item) => FriendReview.fromJson(item as Map<String, dynamic>))
          .toList();

  @override
  Future<Result<ReviewTarget>> fetchTarget(String profileId) => _api.send(
        'GET',
        '/friend-reviews/targets/$profileId',
        (body) => ReviewTarget.fromJson(body as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> create({
    required String revieweeId,
    required List<String> tags,
    String? comment,
  }) =>
      _post({'reviewee_id': revieweeId}, tags, comment);

  @override
  Future<Result<FriendCodeMatch>> lookupFriendCode(String code) => _api.send(
        'POST',
        '/friend-reviews/code-lookup',
        (body) => FriendCodeMatch.fromJson(code, body as Map<String, dynamic>),
        body: {'code': code},
      );

  @override
  Future<Result<void>> createReviewByCode({
    required String friendCode,
    required List<String> tags,
    String? comment,
  }) =>
      _post({'friend_code': friendCode}, tags, comment);

  /// 대상([target] — `reviewee_id` 또는 `friend_code` 하나)만 다르고 몸은 같다.
  Future<Result<void>> _post(Map<String, Object?> target, List<String> tags, String? comment) {
    // 다듬어 비었으면 null 로 보낸다 — 공백만 친 한마디가 리뷰에 남을 이유가 없다.
    final trimmed = comment?.trim() ?? '';
    return _api.send('POST', '/friend-reviews', (_) {}, body: {
      ...target,
      'tags': tags,
      'comment': trimmed.isEmpty ? null : trimmed,
    });
  }
}
