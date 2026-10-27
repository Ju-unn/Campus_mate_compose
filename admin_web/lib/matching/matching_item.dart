/// 매칭 현황(A9) 데이터. 서버 모양은 D4 backend/app/admin/matching.py 의 응답 표 그대로.
/// 사진 · 카톡 아이디 · 대화는 서버도 주지 않고, 와도 읽지 않는다 — 모델에 그 칸이 없다(설계 §8-4c).
library;

import 'package:campus_mate_admin/widgets/status_badge.dart';

class MatchingSummary {
  const MatchingSummary({
    required this.acceptsToday,
    required this.acceptsYesterday,
    required this.acceptsTotal,
    required this.acceptersTotal,
    required this.matchesTotal,
    required this.sharedTotal,
    required this.shareRate,
  });

  final int acceptsToday;

  /// 응답에 없으면 null — 화면이 "어제 n건" 줄을 그리지 않는다(추측 금지)
  final int? acceptsYesterday;
  final int acceptsTotal;
  final int acceptersTotal;
  final int matchesTotal;
  final int sharedTotal;

  /// 공유 쌍 ÷ 매칭 쌍(0~1). 매칭이 없으면 서버가 null 을 준다.
  final double? shareRate;

  /// "62%", 나눌 수 없으면 "-"
  String get shareRatePercent => shareRate == null ? '-' : '${(shareRate! * 100).round()}%';

  static MatchingSummary fromJson(Object? json) {
    if (json case {
      'accepts_today': final int today,
      'accepts_total': final int total,
      'accepters_total': final int accepters,
      'matches_total': final int matches,
      'shared_total': final int shared,
    }) {
      final yesterday = json['accepts_yesterday'];
      final rate = json['share_rate'];
      if (yesterday is int? && rate is num?) {
        return MatchingSummary(
          acceptsToday: today,
          acceptsYesterday: yesterday,
          acceptsTotal: total,
          acceptersTotal: accepters,
          matchesTotal: matches,
          sharedTotal: shared,
          shareRate: rate?.toDouble(),
        );
      }
    }
    throw const FormatException('매칭 요약의 모양이 아니에요');
  }
}

/// 하루치(서버 한국 날짜 글자 그대로)
class DailyMatching {
  const DailyMatching({required this.date, required this.acceptCount, required this.matchCount, required this.shareCount});

  final String date;
  final int acceptCount;
  final int matchCount;
  final int shareCount;

  static DailyMatching fromJson(Object? json) {
    if (json case {'date': final String date, 'accept_count': final int accept, 'match_count': final int match, 'share_count': final int share}) {
      return DailyMatching(date: date, acceptCount: accept, matchCount: match, shareCount: share);
    }
    throw const FormatException('매칭 일별 한 줄의 모양이 아니에요');
  }
}

/// 매칭된 한 사람(닉네임 · 학교 이름 · 프로필 id 뿐)
class MatchPerson {
  const MatchPerson({required this.id, required this.nickname, required this.university});

  final String? id;
  final String? nickname;
  final String? university;

  /// 탈퇴로 프로필이 지워져 닉네임 · id 가 없다 — 링크 없이 "탈퇴한 사용자"
  bool get withdrawn => id == null || nickname == null;

  static MatchPerson fromJson(Object? json) {
    if (json case {'id': final String? id, 'nickname': final String? nickname, 'university': final String? university}) {
      return MatchPerson(id: id, nickname: nickname, university: university);
    }
    throw const FormatException('매칭 상대의 모양이 아니에요');
  }
}

class MatchPair {
  const MatchPair({required this.id, required this.matchedAt, required this.status, required this.sharedAt, required this.a, required this.b});

  final String id;
  final DateTime matchedAt;

  /// `chatting` · `shared` · `closed`
  final String status;
  final DateTime? sharedAt;
  final MatchPerson a;
  final MatchPerson b;

  static MatchPair fromJson(Object? json) {
    if (json case {'id': final String id, 'matched_at': final String at, 'status': final String status}) {
      final matched = DateTime.tryParse(at);
      final shared = json['shared_at'];
      if (matched != null && shared is String?) {
        return MatchPair(
          id: id,
          matchedAt: matched,
          status: status,
          sharedAt: shared == null ? null : DateTime.tryParse(shared),
          a: MatchPerson.fromJson(json['a']),
          b: MatchPerson.fromJson(json['b']),
        );
      }
    }
    throw const FormatException('매칭 한 줄의 모양이 아니에요');
  }
}

/// 상태 → 배지(pen A9: 대화 중 primary-wash · 카톡 공유 완료 success · 닫힘 surface-strong/muted)
(String, StatusTone) matchStatusBadge(String status) {
  return switch (status) {
    'chatting' => ('대화 중', StatusTone.primary),
    'shared' => ('카톡 공유 완료', StatusTone.success),
    'closed' => ('닫힘', StatusTone.neutral),
    _ => (status, StatusTone.neutral),
  };
}

/// 대화 신청 한 줄 — 카드를 받은 사람이 수락한 것. 사진 · 카톡 아이디 · 대화는 서버도 주지 않고 모델에도 자리가 없다.
class MatchRequest {
  const MatchRequest({
    required this.id,
    required this.requestedAt,
    required this.status,
    required this.respondedAt,
    required this.requester,
    required this.target,
  });

  /// 카드 id
  final String id;
  final DateTime requestedAt;

  /// `waiting` · `accepted` · `rejected` · `expired` (받은 사람의 응답)
  final String status;

  /// 응답이 없거나 만료면 null
  final DateTime? respondedAt;

  /// 신청한 사람
  final MatchPerson requester;

  /// 신청을 받은 사람
  final MatchPerson target;

  static MatchRequest fromJson(Object? json) {
    if (json case {'id': final String id, 'requested_at': final String at, 'status': final String status}) {
      final requested = DateTime.tryParse(at);
      final responded = json['responded_at'];
      if (requested != null && responded is String?) {
        return MatchRequest(
          id: id,
          requestedAt: requested,
          status: status,
          respondedAt: responded == null ? null : DateTime.tryParse(responded),
          requester: MatchPerson.fromJson(json['requester']),
          target: MatchPerson.fromJson(json['target']),
        );
      }
    }
    throw const FormatException('대화 신청 한 줄의 모양이 아니에요');
  }
}

/// 신청 상태 → 배지(응답 대기 warning · 수락 success · 거절 danger · 만료 neutral)
(String, StatusTone) requestStatusBadge(String status) {
  return switch (status) {
    'waiting' => ('응답 대기', StatusTone.warning),
    'accepted' => ('수락', StatusTone.success),
    'rejected' => ('거절', StatusTone.danger),
    'expired' => ('만료', StatusTone.neutral),
    _ => (status, StatusTone.neutral),
  };
}

/// 한국 시간(UTC+9) "10/18 14:02"
String formatMonthDayTime(DateTime at) {
  final kst = at.toUtc().add(const Duration(hours: 9));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${kst.month}/${kst.day} ${two(kst.hour)}:${two(kst.minute)}';
}
