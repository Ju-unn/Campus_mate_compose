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
    this.passedAt,
  });

  /// 양쪽이 수락해 카카오톡 아이디·실사진이 공개된 상태.
  final bool passed;

  /// 통과 도장 시각(`matches.trust_passed_at`). 14b 카드를 대화 사이 제자리에 끼우는 데 쓴다(백로그 20).
  /// 이 키를 내려주기 전 서버와도 맞물리게 없으면 null — 그때 카드는 대화 끝에 붙는다.
  final DateTime? passedAt;

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
      passedAt: switch (json['passed_at']) {
        final String at => DateTime.parse(at).toLocal(),
        _ => null,
      },
    );
  }
}

/// 상대가 이 방을 마지막으로 읽은 시각(카톡식 안 읽음 '1', 사용자 결정 2026-10-13 —
/// ERD §4 "상대에게 보이는 읽음 표시는 없다" 를 뒤집었다). 서버 `partner_last_read_at`.
///
/// **키가 없음과 null 을 다르게 읽는다.**
/// - 키가 없다 = 이 값을 내리기 전 서버다 → [PartnerRead.unknown]. '1' 을 하나도 그리지 않는다 —
///   모를 때 전부 '1' 을 붙이면 "상대가 하나도 안 읽었다" 는 거짓말이 되니 안 그리는 쪽이 안전하다.
/// - 키가 있고 null = 상대가 이 방을 한 번도 안 읽었다 → 내 줄 전부가 안 읽음이다.
class PartnerRead {
  const PartnerRead.unknown()
      : _known = false,
        _at = null;

  /// [at] 이 null 이면 "한 번도 안 읽음" 이다(키는 있었다).
  const PartnerRead.known(DateTime? at)
      : _known = true,
        _at = at;

  factory PartnerRead.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey(_key)) {
      return const PartnerRead.unknown();
    }
    return PartnerRead.known(switch (json[_key]) {
      final String at => DateTime.parse(at).toLocal(),
      _ => null,
    });
  }

  static const String _key = 'partner_last_read_at';

  final bool _known;
  final DateTime? _at;

  /// [sentAt] 에 보낸 줄을 상대가 아직 안 읽었는가. **같은 시각은 읽은 것이다** — 서버는 읽은 순간의
  /// 시각을 찍으므로 그 시각까지 들어온 줄은 다 보였다. 둘 다 서버 시각이라 기기 시계와 상관없다.
  bool hasNotRead(DateTime sentAt) {
    final at = _at;
    return _known && (at == null || sentAt.isAfter(at));
  }

  /// 둘 중 **늦게 읽은** 쪽. 상대 읽음 시각은 줄지 않으니, 늦게 도착한 옛 응답이 새 값을 덮어
  /// 사라졌던 '1' 이 되살아나지 않게 한다. 키 없는 응답은 아는 값을 지우지 못한다.
  PartnerRead later(PartnerRead other) {
    final mine = _at;
    final theirs = other._at;
    if (!other._known || theirs == null) {
      return _known ? this : other;
    }
    return mine != null && !theirs.isAfter(mine) ? this : other;
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
    this.myKakaoId,
    this.photoUrls = const [],
    this.partnerRead = const PartnerRead.unknown(),
  });

  final String matchId;
  final ChatPartner partner;

  /// 매칭 성립 시각. 24시간 경과 판정과 카운트다운이 여기서 나온다.
  final DateTime createdAt;
  final TrustGate gate;

  /// **상대** 카카오톡 아이디. 게이트를 통과하기 전에는 null 이다.
  final String? kakaoId;

  /// **내** 카카오톡 아이디. 14f 시트가 "이걸 공유합니다" 로 보여준다 —
  /// 게이트와 상관없이 오고, 앱은 `profile_private` 를 직접 읽을 수 없어 서버가 내려준다.
  final String? myKakaoId;

  /// 상대 실사진 서명 URL. 헤더 아바타가 첫 장으로 바뀐다.
  final List<String> photoUrls;

  /// 상대가 마지막으로 읽은 시각. 메시지 목록 응답에도 같은 값이 오고, 방에 있는 동안은
  /// 사용자 채널의 `read` 이벤트로 바로 받고, 안전망으로 2초(채널이 안 붙었을 때) · 30초(붙었을 때)마다 메시지 1건 조회로
  /// 다시 받는다(머리말은 실사진 서명 URL 때문에 다시 읽지 않는다).
  final PartnerRead partnerRead;

  /// 리마인드 시점을 지났는가 — 14f 시트가 뜨는 조건 하나다.
  bool isReminderDue(DateTime now) => !now.isBefore(createdAt.add(trustGateReminderAfter));

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      matchId: json['match_id'] as String,
      partner: ChatPartner.fromJson(json['partner'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      gate: TrustGate.fromJson(json['gate'] as Map<String, dynamic>),
      kakaoId: json['kakao_id'] as String?,
      myKakaoId: json['my_kakao_id'] as String?,
      photoUrls:
          (json['photo_urls'] as List<dynamic>? ?? []).map((url) => url as String).toList(),
      partnerRead: PartnerRead.fromJson(json),
    );
  }
}
