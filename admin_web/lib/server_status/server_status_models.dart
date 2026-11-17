/// 서버 상태(GET /admin/server-status) · 메뉴 대기 건수(GET /admin/pending-counts). 서버 계약은
/// backend/app/admin/server_status.py · stats.py. 시각은 시각대가 붙은 ISO 글자(checked_at +09:00, 칸 · 이상 +00:00)라
/// 그대로 읽어 같은 순간을 가리키는 DateTime 으로 둔다 — 화면에 쓸 때만 한국 시간으로 바꾼다([formatKstTime]).
library;

/// 최근 3시간을 5분으로 나눈 한 칸. 요청이 없던 칸은 응답 속도 · 서버 수가 null.
class StatusBucket {
  const StatusBucket({
    required this.start,
    required this.requests,
    required this.errors5xx,
    required this.p50Ms,
    required this.p95Ms,
    required this.instances,
  });

  final DateTime start;
  final int requests;
  final int errors5xx;
  final int? p50Ms;
  final int? p95Ms;
  final int? instances;

  static StatusBucket fromJson(Object? json) {
    if (json case {
      'start': final String start,
      'requests': final int requests,
      'errors_5xx': final int errors,
      'p50_ms': final int? p50,
      'p95_ms': final int? p95,
      'instances': final int? instances,
    }) {
      return StatusBucket(start: _time(start), requests: requests, errors5xx: errors, p50Ms: p50, p95Ms: p95, instances: instances);
    }
    throw const FormatException('서버 상태 칸의 모양이 아니에요');
  }
}

/// 서버 `errors` · `error_rate` · `slow`
enum AnomalyKind {
  errors('errors'),
  errorRate('error_rate'),
  slow('slow');

  const AnomalyKind(this.code);

  final String code;

  static AnomalyKind? fromCode(String code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// 기준을 넘은 칸 하나. [value] 는 종류마다 뜻이 다르다: 서버 오류 건수 · 오류 비율(0~1) · 중앙값 응답 시간(밀리초).
class StatusAnomaly {
  const StatusAnomaly({required this.at, required this.kind, required this.value});

  final DateTime at;
  final AnomalyKind kind;
  final double value;
}

/// 마지막 3칸(15분) 요약
class StatusNow {
  const StatusNow({required this.requestsPerMin, required this.errorRate, required this.p50Ms, required this.p95Ms, required this.instances});

  final double requestsPerMin;
  final double errorRate;
  final int? p50Ms;
  final int? p95Ms;
  final int? instances;

  static StatusNow fromJson(Object? json) {
    if (json case {
      'requests_per_min': final num perMin,
      'error_rate': final num rate,
      'p50_ms': final int? p50,
      'p95_ms': final int? p95,
      'instances': final int? instances,
    }) {
      return StatusNow(requestsPerMin: perMin.toDouble(), errorRate: rate.toDouble(), p50Ms: p50, p95Ms: p95, instances: instances);
    }
    throw const FormatException('서버 상태 지금 숫자의 모양이 아니에요');
  }
}

class ServerStatus {
  const ServerStatus({required this.checkedAt, required this.buckets, required this.now, required this.anomalies});

  final DateTime checkedAt;

  /// 오래된 순
  final List<StatusBucket> buckets;
  final StatusNow now;

  /// 최신 순(서버 순서). 모르는 종류의 줄은 버렸다 — 서버가 새 기준을 더해도 화면이 깨지지 않게.
  final List<StatusAnomaly> anomalies;

  static ServerStatus fromJson(Object? json) {
    if (json case {
      'checked_at': final String checkedAt,
      'buckets': final List<Object?> buckets,
      'now': final Object now,
      'anomalies': final List<Object?> anomalies,
    }) {
      return ServerStatus(
        checkedAt: _time(checkedAt),
        buckets: [for (final row in buckets) StatusBucket.fromJson(row)],
        now: StatusNow.fromJson(now),
        anomalies: [
          for (final row in anomalies)
            if (row case {'at': final String at, 'kind': final String code, 'value': final num value})
              if (AnomalyKind.fromCode(code) case final kind?) StatusAnomaly(at: _time(at), kind: kind, value: value.toDouble()),
        ],
      );
    }
    throw const FormatException('서버 상태의 모양이 아니에요');
  }
}

/// 왼쪽 메뉴 배지 숫자(인증샷 검수 · 졸업생 · 신고 · 문의)
class PendingCounts {
  const PendingCounts({required this.heartTasks, required this.graduates, required this.reports, required this.inquiries});

  final int heartTasks;
  final int graduates;
  final int reports;
  final int inquiries;

  static PendingCounts fromJson(Object? json) {
    if (json case {'heart_tasks': final int heartTasks, 'graduates': final int graduates, 'reports': final int reports, 'inquiries': final int inquiries}) {
      return PendingCounts(heartTasks: heartTasks, graduates: graduates, reports: reports, inquiries: inquiries);
    }
    throw const FormatException('대기 건수의 모양이 아니에요');
  }
}

/// 시각대가 없는 글자는 받지 않는다 — 브라우저 시각대로 읽혀 한국 시간이 어긋난다.
DateTime _time(String raw) {
  final at = DateTime.parse(raw);
  if (!at.isUtc) throw const FormatException('시각대가 없는 시각이에요');
  return at;
}

/// 한국 시간 "HH:mm"(브라우저 시각대와 무관)
String formatKstTime(DateTime at) {
  final kst = at.toUtc().add(const Duration(hours: 9));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(kst.hour)}:${two(kst.minute)}';
}

/// 소수 [digits] 자리까지, 끝의 0 은 뗀다(1.20 → "1.2", 42.0 → "42")
String trimNumber(double value, int digits) {
  final fixed = value.toStringAsFixed(digits);
  return fixed.contains('.') ? fixed.replaceFirst(RegExp(r'\.?0+$'), '') : fixed;
}

/// 이상 줄 문구(설계서 · pen vdiey 예시 "오류 비율 6% (5분)")
String anomalyText(StatusAnomaly anomaly) {
  return switch (anomaly.kind) {
    AnomalyKind.errors => '서버 오류 ${anomaly.value.round()}건 (5분)',
    AnomalyKind.errorRate => '오류 비율 ${trimNumber(anomaly.value * 100, 1)}% (5분)',
    AnomalyKind.slow => '응답이 느려요 (보통 ${trimNumber(anomaly.value / 1000, 2)}초)',
  };
}
