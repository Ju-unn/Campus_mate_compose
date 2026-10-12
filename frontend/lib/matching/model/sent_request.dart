import 'package:campus_mate/matching/model/card_profile.dart';

/// 보낸 신청의 상태(`GET /cards/sent` 의 `status`). 판정은 서버가 한다 — 앱은 받은 값을 그대로 그린다.
enum SentRequestStatus { waiting, matched, rejected, expired }

/// 내가 카드에서 "대화 신청하기" 를 누른 한 건(대화 탭 "보낸 신청", 2026-10-13 사용자 결정 B · pen `SentRequestRow` d6otzp).
/// 목록에 남는 기간(거절 · 만료 · 매칭 뒤 7일)과 순서(최신 신청 먼저)도 서버가 정한다.
/// 보낸 시각 · 기한 · 끝난 시각은 화면에 쓰지 않아 읽지 않는다 — 남은 날은 서버의 [daysLeft] 하나만 본다(대장 정정 10-13).
class SentRequest {
  const SentRequest({
    required this.cardId,
    required this.status,
    required this.profile,
    this.daysLeft,
    this.matchId,
  });

  final String cardId;
  final SentRequestStatus status;

  /// 상대 프로필. 서버가 상대 profile_id 는 싣지 않는다.
  final CardProfile profile;

  /// 응답 기한까지 남은 날 — 남은 시간의 올림이라 최소 1 이다. 기다리는 중일 때만 숫자이고 나머지는 null.
  final int? daysLeft;

  /// 매칭된 대화방. 매칭이 아니거나 방을 못 찾으면 null.
  final String? matchId;

  /// 눌러서 대화방으로 갈 수 있는지. 매칭됐어도 방 id 가 없으면 가지 않는다 — 대화 중 목록에 곧 방이 보인다.
  bool get opensChat => status == SentRequestStatus.matched && matchId != null;

  factory SentRequest.fromJson(Map<String, dynamic> json) {
    return SentRequest(
      cardId: json['card_id'] as String,
      status: SentRequestStatus.values.byName(json['status'] as String),
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      daysLeft: json['days_left'] as int?,
      matchId: json['match_id'] as String?,
    );
  }
}
