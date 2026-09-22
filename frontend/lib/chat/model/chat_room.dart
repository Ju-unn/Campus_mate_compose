import 'package:campus_mate/chat/model/conversation.dart';

/// 매칭 성립부터 응답 기한까지의 길이. 서버 `gate.GATE_DEADLINE` 과 같은 값이다.
const Duration trustGateDeadline = Duration(hours: 48);

/// 리마인드가 오는 시점. **수락은 매칭 순간부터 할 수 있고**(결정 10) 이 시각은
/// 14f 시트가 방에 들어올 때마다 뜨기 시작하는 경계일 뿐이다.
const Duration trustGateReminderAfter = Duration(hours: 24);

/// 신뢰 확인 게이트의 현 상태(화면 14f · 14g · 14h · 14b 가 이 하나로 갈린다).
class TrustGate {
  const TrustGate({
    required this.passed,
    required this.partnerLeft,
    required this.deadlineAt,
    this.myResponse,
  });

  /// 양쪽이 수락해 카카오톡 아이디·실사진이 공개된 상태.
  final bool passed;

  /// 상대가 나간 방. 게이트가 멈춘다 — 배너도 시트도 뜨지 않는다(결정 7).
  final bool partnerLeft;

  /// 매칭 성립 + 48시간. 카운트다운은 이 값에서 **기기 시계로** 뺀다.
  final DateTime deadlineAt;

  /// `'accept'` 또는 null. 거절이라는 값은 없다 — 거절한 사람은 방을 떠난다(결정 11).
  final String? myResponse;

  bool get accepted => myResponse == 'accept';

  Duration remaining(DateTime now) {
    final left = deadlineAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  factory TrustGate.fromJson(Map<String, dynamic> json) {
    return TrustGate(
      passed: json['passed'] as bool? ?? false,
      partnerLeft: json['partner_left'] as bool? ?? false,
      deadlineAt: DateTime.parse(json['deadline_at'] as String).toLocal(),
      myResponse: json['my_response'] as String?,
    );
  }
}

/// 채팅방 머리말(화면 14). 카카오톡 아이디와 실사진은 **통과한 뒤에만** 담겨 온다 —
/// 통과 전에는 응답에 키 자체가 없다(설계 §2.5).
class ChatRoom {
  const ChatRoom({
    required this.matchId,
    required this.partner,
    required this.createdAt,
    required this.gate,
    this.kakaoId,
    this.photoUrls = const [],
  });

  final String matchId;
  final ChatPartner partner;

  /// 매칭 성립 시각. 24시간 경과 판정과 카운트다운이 여기서 나온다.
  final DateTime createdAt;
  final TrustGate gate;
  final String? kakaoId;

  /// 상대 실사진 서명 URL. 헤더 아바타가 첫 장으로 바뀐다.
  final List<String> photoUrls;

  /// 리마인드 시점을 지났는가 — 14f 시트가 뜨는 조건 하나다.
  bool isReminderDue(DateTime now) => !now.isBefore(createdAt.add(trustGateReminderAfter));

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      matchId: json['match_id'] as String,
      partner: ChatPartner.fromJson(json['partner'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      gate: TrustGate.fromJson(json['gate'] as Map<String, dynamic>),
      kakaoId: json['kakao_id'] as String?,
      photoUrls:
          (json['photo_urls'] as List<dynamic>? ?? []).map((url) => url as String).toList(),
    );
  }
}
