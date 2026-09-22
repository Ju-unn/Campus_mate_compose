import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';

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

  @override
  Future<Result<void>> markRead(String matchId) =>
      _api.send('PATCH', '/chat/matches/$matchId/read', (_) {});

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
