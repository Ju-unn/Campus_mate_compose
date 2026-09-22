import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/common/result.dart';

/// 한 번에 받아 오는 메시지 수(결정 9). 서버 `MESSAGE_PAGE_SIZE` 와 같은 값이다.
const int messagePageSize = 50;

/// 메시지 한 통의 글자 수 상한(결정 8). 서버 `MESSAGE_MAX_LENGTH` 와 같은 값이다.
const int messageMaxLength = 1000;

/// 메시지 한 페이지.
class MessagePage {
  const MessagePage({required this.messages, required this.hasMore});

  /// **오래된 것부터** 담겨 있다. 서버는 최신순으로 주지만 화면이 쓰는 순서로 한 번만 뒤집는다.
  final List<Message> messages;
  final bool hasMore;

  factory MessagePage.fromJson(Map<String, dynamic> json) {
    return MessagePage(
      messages: Message.listFromJson(json['messages'] as List<dynamic>).reversed.toList(),
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

/// 신뢰 확인 수락의 결과. 양쪽이 수락됐을 때만 [kakaoId] 가 담긴다.
class TrustAcceptOutcome {
  const TrustAcceptOutcome({required this.passed, this.kakaoId});

  final bool passed;
  final String? kakaoId;

  factory TrustAcceptOutcome.fromJson(Map<String, dynamic> json) {
    return TrustAcceptOutcome(
      passed: json['passed'] as bool? ?? false,
      kakaoId: json['kakao_id'] as String?,
    );
  }
}

/// 조각 5 가 쓰는 서버 호출 전부. 화면은 이 인터페이스만 보고 `Http…` 구현을 모른다.
///
/// **거절 전용 호출이 없다** — 게이트 거절은 [leave] 다(결정 11).
abstract interface class ChatRepository {
  Future<Result<List<Conversation>>> fetchConversations();
  Future<Result<ChatRoom>> fetchRoom(String matchId);

  /// [before] · [beforeId] 는 화면에 있는 **가장 오래된 줄** 의 값을 그대로 보낸다.
  /// 시각만 보내면 같은 시각에 들어간 두 줄이 페이지 경계에서 한 줄 빠진다.
  Future<Result<MessagePage>> fetchMessages(String matchId, {DateTime? before, String? beforeId});

  /// 보낸 줄을 돌려준다. 모르는 종류였다면 null 이고, 그때는 구독이 붙여 준다.
  Future<Result<Message?>> sendMessage(String matchId, String body);

  /// 방에 들어올 때와 나갈 때 한 번씩. 상대에게 보이는 읽음 표시는 없다.
  Future<Result<void>> markRead(String matchId);

  /// 나가기 = 게이트 거절(결정 11). 되돌릴 수 없고 상대에게 시스템 줄로 보인다.
  Future<Result<void>> leave(String matchId);

  Future<Result<TrustAcceptOutcome>> acceptTrust(String matchId);
}
