/// 관리자 로그인 · 2단계(TOTP)에 필요한 일만 모은 경계. 실제는 Supabase([SupabaseAdminAuth]),
/// 시험은 가짜를 provider 로 갈아 끼운다.
abstract interface class AdminAuth {
  bool get hasSession;

  /// 서버 호출에 Bearer 로 붙일 토큰. 세션이 없으면 null.
  String? get accessToken;

  String? get email;

  /// 관문을 다시 판정해야 하는 사건(로그인 · 로그아웃 · 2단계 확인)마다 한 번씩 알린다.
  Stream<void> get changes;

  /// 구글 로그인 페이지로 이동한다(돌아오면 [changes] 가 알린다).
  Future<void> signInWithGoogle();

  Future<MfaState> mfaState();

  /// 새 TOTP 를 등록하고 인증 앱에 넣을 비밀 키를 돌려준다.
  Future<TotpEnrollment> enrollTotp();

  /// 6자리 코드로 challenge + verify. 성공하면 세션이 aal2 가 된다.
  Future<VerifyOutcome> verifyTotp({required String factorId, required String code});

  Future<void> signOut();
}

class MfaState {
  const MfaState({required this.aal2, required this.factorId});

  /// 지금 세션이 2단계까지 마쳤는지(aal2)
  final bool aal2;

  /// 확인까지 끝난 TOTP. 없으면 아직 등록 전이다.
  final String? factorId;
}

class TotpEnrollment {
  const TotpEnrollment({required this.factorId, required this.secret});

  final String factorId;

  /// 인증 앱에 직접 넣는 base32 비밀 키(QR 대신, 설계서 §5)
  final String secret;
}

enum VerifyOutcome { ok, wrongCode, failed }
