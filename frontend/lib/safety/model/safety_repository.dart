import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/safety/model/partner_profile.dart';
import 'package:campus_mate/safety/model/report_reason.dart';

/// 무엇을 신고하는가 — 프로필 · 메시지 · 지인 리뷰(20c, 차단 안 함 — 서버 B3) · 투표 글(차단 안 함 — 서버 #191).
class ReportTarget {
  /// 채팅방 앱바 메뉴 · 14c 하단 액션 행에서 온 신고.
  const ReportTarget.profile(String profileId) : _type = 'profile', _id = profileId;

  /// 말풍선 롱프레스에서 온 신고. 서버가 이 id 로 본문 · 보낸 시각을 스냅샷에 담는다(B1 ③).
  const ReportTarget.message(String messageId) : _type = 'message', _id = messageId;

  const ReportTarget.friendReview(String reviewId) : _type = 'friend_review', _id = reviewId;

  /// 15d 목록 · 17c 상세의 투표 카드 머리줄에서 온 신고 — 남의 글만(내 글은 서버도 404).
  const ReportTarget.poll(String pollId) : _type = 'poll', _id = pollId;

  final String _type;
  final String _id;

  Map<String, String> toJson() => {'target_type': _type, 'target_id': _id};
}

/// 16f 차단 목록 한 줄. **아바타만 온다** — 실사진은 서버가 주지 않는다(B2).
class BlockedUser {
  const BlockedUser({
    required this.profileId,
    required this.nickname,
    required this.blockedAt,
    this.avatarUrl,
  });

  final String profileId;
  final String nickname;
  final String? avatarUrl;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    return BlockedUser(
      profileId: json['profile_id'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatar_url'] as String?,
      // 서버는 UTC(+00:00) 로 준다. 화면은 차단일을 기기 날짜로 보여 준다.
      blockedAt: DateTime.parse(json['blocked_at'] as String).toLocal(),
    );
  }
}

/// 조각 6 신고 · 차단 서버 호출. 둘이 늘 함께 움직여(신고하면 차단된다, 결정 4) 인터페이스 하나로 둔다.
abstract interface class SafetyRepository {
  /// [note] 는 [ReportReason.other] 일 때만 서버로 간다. 사유를 바꿔도 화면이 메모를 비울 필요가 없다.
  Future<Result<void>> report({
    required ReportTarget target,
    required ReportReason reason,
    String? note,
  });

  /// 이미 차단돼 있어도 성공이다(서버가 200) — 재시도해도 안전하다.
  Future<Result<void>> block(String profileId);

  /// 최신 차단이 먼저 온다.
  Future<Result<List<BlockedUser>>> fetchBlocks();

  /// 해제해도 대화는 돌아오지 않는다(16f 문구). 이미 없는 행이어도 성공이다.
  Future<Result<void>> unblock(String profileId);

  /// 14c 상대 프로필. 차단 · 나감 · 탈퇴는 모두 같은 404 로 온다(차단 사실이 새지 않게).
  Future<Result<PartnerProfile>> fetchPartnerProfile(String profileId);
}
