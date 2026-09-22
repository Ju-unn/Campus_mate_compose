import 'package:campus_mate/chat/model/message.dart';

/// 채팅 상대(목록 행·방 헤더 공용). 나이·학과는 담기지 않는다 —
/// 그건 카드에서 이미 본 것이고, 여기서 다시 보여줄 자리가 없다.
class ChatPartner {
  const ChatPartner({required this.profileId, required this.nickname, this.avatarUrl});

  final String profileId;
  final String nickname;

  /// 표시용 만화 아바타. 신뢰 확인을 통과해도 이 자리가 실사진으로 바뀌는 것은
  /// 방 헤더뿐이고 목록은 아바타 그대로다(§5.2).
  final String? avatarUrl;

  factory ChatPartner.fromJson(Map<String, dynamic> json) {
    return ChatPartner(
      profileId: json['profile_id'] as String,
      // 닉네임은 온보딩 필수라 비는 일이 없지만, 서버가 null 을 주면 행이 통째로
      // 안 그려지는 것보다 빈 이름으로라도 열리는 편이 낫다.
      nickname: json['nickname'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

/// 대화 목록 한 줄(화면 13 "대화 중", pen `L061P2`).
/// 닫힌 방과 내가 나간 방은 **서버가 이미 빼고 준다** — 앱에 거르는 코드가 없다.
class Conversation {
  const Conversation({
    required this.matchId,
    required this.partner,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.trustPassed,
    required this.remainingSeconds,
    this.lastMessage,
    this.lastMessageKind,
    this.myTrustResponse,
  });

  final String matchId;
  final ChatPartner partner;

  /// 마지막 줄이 없으면(첫 대화 전) 매칭 시각. 정렬은 이 값 하나로 한다.
  final DateTime lastMessageAt;
  final int unreadCount;
  final bool trustPassed;

  /// 매칭 성립 + 48시간까지 남은 시간. 0 이면 곧 목록에서 사라진다.
  final int remainingSeconds;

  /// 미리보기 한 줄. 시스템 줄("OO님이 채팅방을 나갔어요")도 그냥 마지막 메시지다.
  final String? lastMessage;
  final MessageKind? lastMessageKind;

  /// `'accept'` 또는 null. 거절은 값이 아니라 나가기로 남는다(결정 11).
  final String? myTrustResponse;

  bool get hasAccepted => myTrustResponse == 'accept';

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      matchId: json['match_id'] as String,
      partner: ChatPartner.fromJson(json['partner'] as Map<String, dynamic>),
      lastMessageAt: DateTime.parse(json['last_message_at'] as String).toLocal(),
      unreadCount: json['unread_count'] as int? ?? 0,
      trustPassed: json['trust_passed'] as bool? ?? false,
      remainingSeconds: json['remaining_seconds'] as int? ?? 0,
      lastMessage: json['last_message'] as String?,
      lastMessageKind: json['last_message_kind'] == null
          ? null
          : MessageKind.fromWire(json['last_message_kind'] as String),
      myTrustResponse: json['my_trust_response'] as String?,
    );
  }
}
