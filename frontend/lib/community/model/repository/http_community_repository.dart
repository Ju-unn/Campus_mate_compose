import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/data/feed_page.dart';
import 'package:campus_mate/community/model/data/notice.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/model/repository/community_repository.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [CommunityRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류와 세션 확인은
/// `sendAuthorizedRequest` 가 이미 하므로 여기서는 URL · 바디 · 파싱만 맡는다.
/// 오류 문구는 서버 `detail` 그대로 실패에 실린다(view 가 `context.errorText`).
class HttpCommunityRepository implements CommunityRepository {
  const HttpCommunityRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<FeedPage<CommunityItem>>> fetchFeed({
    CommunityFeedTab tab = CommunityFeedTab.all,
    PageCursor? before,
  }) {
    final query = {
      // 전체는 보내지 않는다 — 서버 기본값이 all 이다.
      if (tab != CommunityFeedTab.all) 'tab': tab.toWire(),
      ...?before?.toQuery('before'),
    };
    return _api.send(
      'GET',
      '/community/feed',
      (body) => FeedPage.fromJson(body as Map<String, dynamic>, CommunityItem.fromJson),
      // 전체 첫 쪽에는 쿼리가 없다. 빈 맵을 주면 URL 끝에 '?' 가 붙는다.
      query: query.isEmpty ? null : query,
    );
  }

  @override
  Future<Result<CommunityItem>> fetchItem(String itemId) => _api.send(
        'GET',
        '/community/items/$itemId',
        (body) => CommunityItem.fromJson((body as Map<String, dynamic>)['item'] as Map<String, dynamic>),
      );

  @override
  Future<Result<FeedPage<Notice>>> fetchNotices({PageCursor? before}) => _api.send(
        'GET',
        '/community/notices',
        (body) => FeedPage.fromJson(body as Map<String, dynamic>, Notice.fromJson),
        // 첫 쪽에는 쿼리가 없다 — 빈 맵을 주면 URL 끝에 '?' 가 붙는다.
        query: before?.toQuery('before'),
      );

  @override
  Future<Result<void>> createPoll({
    required CommunityCategory category,
    required String question,
    required String optionA,
    required String optionB,
  }) =>
      _api.send(
        'POST',
        '/community/polls',
        (_) {},
        body: {
          'question': question,
          'option_a_label': optionA,
          'option_b_label': optionB,
          'category': category.toWire(),
        },
      );

  @override
  Future<Result<void>> createPost({required CommunityCategory category, required String body}) => _api.send(
        'POST',
        '/community/posts',
        (_) {},
        body: {'category': category.toWire(), 'body': body},
      );

  @override
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice) => _api.send(
        'POST',
        '/community/polls/$pollId/votes',
        (body) => VoteOutcome.fromJson(body as Map<String, dynamic>),
        body: {'choice': choice.name},
      );

  @override
  Future<Result<void>> deleteItem(String itemId) => _api.send('DELETE', '/community/items/$itemId', (_) {});

  @override
  Future<Result<FeedPage<PollComment>>> fetchComments(String itemId, {PageCursor? after}) => _api.send(
        'GET',
        '/community/items/$itemId/comments',
        (body) => FeedPage.fromJson(body as Map<String, dynamic>, PollComment.fromJson),
        // 첫 쪽에는 쿼리가 없다 — 빈 맵을 주면 URL 끝에 '?' 가 붙는다.
        query: after?.toQuery('after'),
      );

  @override
  Future<Result<PollComment>> addComment(String itemId, String body) => _api.send(
        'POST',
        '/community/items/$itemId/comments',
        (json) => PollComment.fromJson(json as Map<String, dynamic>),
        body: {'body': body},
      );

  @override
  Future<Result<void>> deleteComment(String commentId) =>
      _api.send('DELETE', '/community/comments/$commentId', (_) {});
}
