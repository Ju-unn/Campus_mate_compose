import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [VerificationGateRepository]를 FastAPI 호출로 구현한다.
class HttpVerificationGateRepository implements VerificationGateRepository {
  const HttpVerificationGateRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<VerificationGate>> fetchGate() =>
      _api.send('GET', '/me/verification-status', _toGate);

  VerificationGate _toGate(Object body) {
    final fields = body as Map<String, dynamic>;
    // 칸이 없으면(동의 관문 전의 옛 서버) 지금 규칙 그대로 — 없는 POST /me/consents 앞에 갇히지 않게.
    return switch (fields['consent']) {
      'none' => VerificationGate.needsConsent,
      'outdated' => VerificationGate.needsConsentRenewal,
      _ => _toGateAfterConsent(fields),
    };
  }

  /// 동의 다음은 학교 메일, 그다음이 학생증 · 학과다.
  /// ponytail: 칸이 없으면(학교 메일 관문 전의 옛 서버) 인증된 것으로 본다 — 서버 배포 뒤 제거 가능.
  /// `false` 일 때만 막는다. 칸이 없는데 막으면 없는 POST /school-email/verify 앞에 갇힌다.
  VerificationGate _toGateAfterConsent(Map<String, dynamic> fields) {
    if (fields['school_email_verified'] == false) {
      return VerificationGate.needsSchoolEmail;
    }
    return _toGateFrom(fields['status'] as String, fields['has_school_info'] as bool);
  }

  VerificationGate _toGateFrom(String status, bool hasSchoolInfo) {
    if (status != 'verified') {
      return VerificationGate.needsStudentVerification;
    }
    if (!hasSchoolInfo) {
      return VerificationGate.needsSchoolInfo;
    }
    return VerificationGate.complete;
  }
}
