/// 미등록 학교 메일 도메인 한 줄(A6). 서버 모양은 D4 `GET /admin/unknown-domains` — 많은 순.
class UnknownDomain {
  const UnknownDomain({required this.domain, required this.attemptCount, required this.lastSeenAt});

  final String domain;
  final int attemptCount;
  final DateTime lastSeenAt;

  static UnknownDomain fromJson(Object? json) {
    if (json case {'domain': final String domain, 'attempt_count': final int count, 'last_seen_at': final String at}) {
      final seen = DateTime.tryParse(at);
      if (seen != null) return UnknownDomain(domain: domain, attemptCount: count, lastSeenAt: seen);
    }
    throw const FormatException('미등록 학교 메일 한 줄의 모양이 아니에요');
  }
}
