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
  Future<Result<PollPage>> fetchPolls({DateTime? before, String? beforeId}) => _api.send(
        'GET',
        '/community/polls',
        (body) => PollPage.fromJson(body as Map<String, dynamic>),
        // 첫 쪽에는 커서가 없다. 빈 맵을 주면 URL 끝에 '?' 가 붙는다.
        query: before == null ? null : {'before': before.toUtc().toIso8601String(), 'before_id': ?beforeId},
      );

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
