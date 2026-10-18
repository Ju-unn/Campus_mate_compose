/// 홈(A2) 데이터. 서버 모양은 D4 backend/app/admin/stats.py · health.py 의 응답 표 그대로(칸 이름 추측 없음).
library;

class HomeStats {
  const HomeStats({required this.pendingProofs, required this.openReports, required this.signupsToday});

  final int pendingProofs;
  final int openReports;
  final int signupsToday;

  static HomeStats fromJson(Object? json) {
    if (json case {'open_reports': final int reports, 'pending_proofs': final int proofs, 'signups_today': final int today}) {
      return HomeStats(pendingProofs: proofs, openReports: reports, signupsToday: today);
    }
    throw const FormatException('홈 통계의 모양이 아니에요');
  }
}

/// 하루치(서버 한국 날짜 글자 그대로 — "2026-10-18")
class DailyStat {
  const DailyStat({
    required this.date,
    required this.maleSignups,
    required this.femaleSignups,
    required this.reportCount,
    required this.proofCount,
  });

  final String date;
  final int maleSignups;
  final int femaleSignups;
  final int reportCount;
  final int proofCount;

  static DailyStat fromJson(Object? json) {
    if (json case {
      'date': final String date,
      'male_signups': final int male,
      'female_signups': final int female,
      'report_count': final int reports,
      'proof_count': final int proofs,
    }) {
      return DailyStat(date: date, maleSignups: male, femaleSignups: female, reportCount: reports, proofCount: proofs);
    }
    throw const FormatException('일별 통계 한 줄의 모양이 아니에요');
  }
}

class UniversityStatus {
  const UniversityStatus({
    required this.id,
    required this.name,
    required this.cardOpensAt,
    required this.maleActive,
    required this.femaleActive,
  });

  final String id;
  final String name;
  final DateTime? cardOpensAt;
  final int maleActive;
  final int femaleActive;

  static UniversityStatus fromJson(Object? json) {
    if (json case {'id': final String id, 'name': final String name, 'male_active': final int male, 'female_active': final int female}) {
      final opens = json['card_opens_at'];
      return UniversityStatus(
        id: id,
        name: name,
        cardOpensAt: opens is String ? DateTime.tryParse(opens) : null,
        maleActive: male,
        femaleActive: female,
      );
    }
    throw const FormatException('학교 한 줄의 모양이 아니에요');
  }
}

/// 가로 막대의 학교 이름: "서울대학교" → "서울대"(pen). "…대학교" 가 아니면 그대로.
String shortSchoolName(String name) => name.endsWith('대학교') ? name.substring(0, name.length - 2) : name;

/// 운영 상태판 한 줄. [status] 는 서버 판정 `ok` · `warn` · `alert` · `na`(카드 줄만 — 지금은 점검 대상 아님).
class HealthItem {
  const HealthItem({required this.key, required this.status, required this.count});

  final String key;
  final String status;
  final int count;

  static HealthItem fromJson(Object? json) {
    if (json case {'key': final String key, 'status': final String status, 'count': final int count}) {
      return HealthItem(key: key, status: status, count: count);
    }
    throw const FormatException('상태판 한 줄의 모양이 아니에요');
  }
}

class HealthReport {
  const HealthReport({required this.items, required this.unobservable});

  final List<HealthItem> items;

  /// 서버가 볼 수 없는 점검(`refund_batch`)
  final List<String> unobservable;

  static HealthReport fromJson(Object? json) {
    if (json case {'items': final List<Object?> items, 'unobservable': final List<Object?> unobservable}) {
      return HealthReport(items: [for (final row in items) HealthItem.fromJson(row)], unobservable: unobservable.whereType<String>().toList());
    }
    throw const FormatException('운영 상태판의 모양이 아니에요');
  }
}

const Map<String, (String, String)> _health = {
  'cards_issued_today': ('오늘 카드가 도착했는지 (지급 요일 기준)', '곳'),
  'stuck_chat_rooms': ('48시간 지나도 안 닫힌 방', '개'),
  'overdue_withdrawn': ('탈퇴 31일 넘은 미삭제 프로필', '명'),
  'avatar_failures_24h': ('최근 24시간 아바타 생성 실패', '건'),
  'stuck_pending_pushes': ('오래 쌓인 푸시', '건'),
};

/// 상태판 줄 문구(pen A2 aB4TU). 모르는 키는 null — 화면이 그 줄을 그리지 않는다.
String? healthLabel(String key) => _health[key]?.$1;

/// 이상 줄 배지 글자: pen "2개"(방) · "4건"(아바타 실패). 나머지 단위는 같은 결로 이어 정했다(카드 곳 · 프로필 명 · 푸시 건).
String healthCountLabel(String key, int count) => '$count${_health[key]?.$2 ?? '건'}';
