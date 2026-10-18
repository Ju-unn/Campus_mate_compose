/// 로그인 관문의 단계. 라우터가 단계마다 보낼 화면을 고른다(router/admin_router.dart).
sealed class GateStage {
  const GateStage();
}

/// dart-define 값이 빠졌다 — 빠진 이름들을 보여 준다
final class ConfigMissing extends GateStage {
  const ConfigMissing(this.keys);
  final List<String> keys;
}

/// A0 로그인
final class SignedOut extends GateStage {
  const SignedOut();
}

/// A1 등록 — 확인된 TOTP 가 없다
final class EnrollMfa extends GateStage {
  const EnrollMfa();
}

/// A1 입력 — TOTP 는 있는데 세션이 aal1
final class VerifyMfa extends GateStage {
  const VerifyMfa(this.factorId);
  final String factorId;
}

/// 공통 "2단계 인증이 필요해요" — 서버가 403 mfa_required 로 거절했다. factor 가 없으면 등록으로 간다
final class MfaRequired extends GateStage {
  const MfaRequired(this.factorId);
  final String? factorId;
}

/// 공통 "권한 없음" — 서버가 403 not_admin
final class NotAdmin extends GateStage {
  const NotAdmin();
}

/// 서버에 닿지 못했다(연결 실패 · 5xx · 모르는 응답)
final class Unavailable extends GateStage {
  const Unavailable();
}

/// 셸로 들어간다
final class Ready extends GateStage {
  const Ready(this.email);
  final String email;
}
