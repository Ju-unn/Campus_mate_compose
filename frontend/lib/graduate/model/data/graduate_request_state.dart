/// 관리자가 고르는 반려 사유 코드(계획서 D10). 문구는 pen 문구표가 확정되면 화면 쪽에서 붙인다.
enum GraduateRejectReason {
  unreadable('unreadable'),
  notCertificate('not_certificate'),
  unverifiable('unverifiable'),
  schoolUnsupported('school_unsupported');

  const GraduateRejectReason(this.code);

  final String code;

  static GraduateRejectReason? tryParse(Object? code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }
}

/// 서버 `verification-status.graduate` 의 두 상태. 신청이 없거나 취소됐으면 값이 없다(null).
sealed class GraduateRequestState {
  const GraduateRequestState();

  /// 모르는 상태 · 객체가 아닌 값은 null. `attempts_left` 가 없으면 0 으로 본다.
  static GraduateRequestState? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final attemptsLeft = json['attempts_left'] is int ? json['attempts_left'] as int : 0;
    return switch (json['state']) {
      'pending' => GraduatePending(attemptsLeft: attemptsLeft, submittedAt: _dateOrNull(json['submitted_at'])),
      'rejected' =>
        GraduateRejected(reason: GraduateRejectReason.tryParse(json['reject_reason']), attemptsLeft: attemptsLeft),
      _ => null,
    };
  }

  static DateTime? _dateOrNull(Object? value) => value is String ? DateTime.tryParse(value) : null;
}

/// 심사 중. [submittedAt] 은 서버가 안 주면 null.
final class GraduatePending extends GraduateRequestState {
  const GraduatePending({required this.attemptsLeft, this.submittedAt});

  final int attemptsLeft;
  final DateTime? submittedAt;
}

/// 반려됨. [reason] 은 서버가 모르는 코드를 주면 null — 그래도 반려다.
final class GraduateRejected extends GraduateRequestState {
  const GraduateRejected({required this.reason, required this.attemptsLeft});

  final GraduateRejectReason? reason;
  final int attemptsLeft;

  /// 남은 신청 횟수가 없다 — 앱은 신청 폼 대신 문의 안내를 보인다.
  bool isExhausted() => attemptsLeft <= 0;
}
