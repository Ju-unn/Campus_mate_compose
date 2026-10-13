import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/http_send.dart';

/// [ChatRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류와 세션 확인은
/// `sendAuthorizedRequest` 가 이미 하므로 여기서는 URL·바디·파싱만 맡는다.
class HttpChatRepository implements ChatRepository {
  const HttpChatRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<List<Conversation>>> fetchConversations() => _api.send(
        'GET',
        '/chat/conversations',
        (body) => ((body as Map<String, dynamic>)['conversations'] as List<dynamic>)
            .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  @override
  Future<Result<ChatRoom>> fetchRoom(String matchId) => _api.send(
        'GET',
        '/chat/matches/$matchId',
        (body) => ChatRoom.fromJson(body as Map<String, dynamic>),
      );

  @override
  Future<Result<MessagePage>> fetchMessages(
    String matchId, {
    DateTime? before,
    String? beforeId,
  }) =>
      _api.send(
        'GET',
        '/chat/matches/$matchId/messages',
        (body) => MessagePage.fromJson(body as Map<String, dynamic>),
        query: {
          'limit': '$messagePageSize',
          // 첫 페이지에는 커서가 없다. 빈 문자열을 보내면 서버가 422 로 막는다.
          if (before != null) 'before': before.toUtc().toIso8601String(),
          'before_id': ?beforeId,
        },
      );

  @override
  Future<Result<Message?>> sendMessage(String matchId, String body) => _api.send(
        'POST',
        '/chat/matches/$matchId/messages',
        (response) =>
            Message.fromJson((response as Map<String, dynamic>)['message'] as Map<String, dynamic>),
        body: {'body': body},
      );

  /// 쓰기 가운데 이것만 조회와 같은 [readTimeout] 에 끊는다(대장 결정 10-13) — 다시 찍어도 해가 없고, 방에 들어올 때
  /// 이게 끝나야 상대 읽음 확인이 시작된다(응답이 끝내 안 오면 그 방문 내내 '1' 이 남았다). 다른 쓰기는 그대로 기다린다.
  @override
  Future<Result<void>> markRead(String matchId) => _api
      .send('PATCH', '/chat/matches/$matchId/read', (_) {})
      .timeout(readTimeout, onTimeout: () => const FailureResult(NetworkFailure()));

  @override
  Future<Result<PartnerRead>> fetchPartnerRead(String matchId) => _api.send(
        'GET',
        '/chat/matches/$matchId/messages',
        (body) => PartnerRead.fromJson(body as Map<String, dynamic>),
        // 줄은 쓰지 않는다 — 서버가 응답마다 붙이는 partner_last_read_at 만 본다.
        query: {'limit': '1'},
      );

  @override
  Future<Result<void>> leave(String matchId) =>
      _api.send('POST', '/chat/matches/$matchId/leave', (_) {});

  @override
  Future<Result<TrustAcceptOutcome>> acceptTrust(String matchId) => _api.send(
        'POST',
        // 바디가 없다 — 수락 전용이라 고를 것이 없다(결정 11).
        '/chat/matches/$matchId/trust',
        (body) => TrustAcceptOutcome.fromJson(body as Map<String, dynamic>),
      );
}
