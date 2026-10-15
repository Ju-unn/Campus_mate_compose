import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [CommunityRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류와 세션 확인은
/// `sendAuthorizedRequest` 가 이미 하므로 여기서는 URL · 바디 · 파싱만 맡는다.
class HttpCommunityRepository implements CommunityRepository {
  const HttpCommunityRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<PollPage>> fetchPolls({PollFeedTab tab = PollFeedTab.all, DateTime? before, String? beforeId}) {
    final query = {
      // 전체는 보내지 않는다 — 서버 기본값이 all 이고, 탭 전 앱과 같은 URL 이 된다.
      if (tab != PollFeedTab.all) 'tab': tab.name,
      if (before != null) ...{'before': before.toUtc().toIso8601String(), 'before_id': ?beforeId},
    };
    return _api.send(
      'GET',
      '/community/polls',
      (body) => PollPage.fromJson(body as Map<String, dynamic>),
      // 전체 첫 쪽에는 쿼리가 없다. 빈 맵을 주면 URL 끝에 '?' 가 붙는다.
      query: query.isEmpty ? null : query,
    );
  }

  @override
  Future<Result<Poll>> fetchPoll(String pollId) => _api.send(
        'GET',
        '/community/polls/$pollId',
        (body) => Poll.fromJson((body as Map<String, dynamic>)['poll'] as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> createPoll({
    required String question,
    required String optionA,
    required String optionB,
  }) =>
      _api.send(
        'POST',
        '/community/polls',
        (_) {},
        body: {'question': question, 'option_a_label': optionA, 'option_b_label': optionB},
      );

  @override
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice) => _api.send(
        'POST',
        '/community/polls/$pollId/votes',
        (body) => VoteOutcome.fromJson(body as Map<String, dynamic>),
        body: {'choice': choice.name},
      );

  @override
  Future<Result<void>> deletePoll(String pollId) =>
      _api.send('DELETE', '/community/polls/$pollId', (_) {});
}
