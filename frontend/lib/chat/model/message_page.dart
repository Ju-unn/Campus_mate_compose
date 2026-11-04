import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/message.dart';

/// 한 번에 받아 오는 메시지 수(결정 9). 서버 `MESSAGE_PAGE_SIZE` 와 같은 값이다.
const int messagePageSize = 50;

/// 메시지 한 통의 글자 수 상한(결정 8). 서버 `MESSAGE_MAX_LENGTH` 와 같은 값이다.
const int messageMaxLength = 1000;

/// 메시지 한 페이지.
class MessagePage {
  const MessagePage({
    required this.messages,
    required this.hasMore,
    this.partnerRead = const PartnerRead.unknown(),
  });

  /// **오래된 것부터** 담겨 있다. 서버는 최신순으로 주지만 화면이 쓰는 순서로 한 번만 뒤집는다.
  final List<Message> messages;
  final bool hasMore;

  /// 상대가 마지막으로 읽은 시각. 방 머리말과 같은 값이다.
  final PartnerRead partnerRead;

  factory MessagePage.fromJson(Map<String, dynamic> json) {
    return MessagePage(
      messages: Message.listFromJson(json['messages'] as List<dynamic>).reversed.toList(),
      hasMore: json['has_more'] as bool? ?? false,
      partnerRead: PartnerRead.fromJson(json),
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
