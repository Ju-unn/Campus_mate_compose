import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';

/// go_router 가 다음 화면을 정할 때만 쓰는 굵은 단위 상태.
/// 학생증(3b) 관문은 2026-10-17 에 없앴다 — 학교 메일 다음이 바로 학과(3c)다.
enum VerificationGate {
  /// 아직 묻는 중이다(앱을 켠 직후 · 로그아웃 뒤). 스플래시에 머문다 — 동의 화면이 깜빡이지 않게(결정 13).
  unknown,

  /// 처음 묻는 것부터 실패했다. 01-1 인터넷 없음 화면에서 "다시 시도" 를 기다린다(결정 13, B10).
  /// 한 번이라도 알아낸 뒤의 실패는 이 값이 되지 않는다 — 아는 관문을 그대로 쓴다.
  unreachable,

  /// 약관 동의(02-c)가 첫 관문이다 — 동의 전에는 학교 메일을 받지 않는다.
  needsConsent,

  /// 약관이 바뀌어 다시 동의해야 한다(02-c-4). 온보딩을 마친 계정도 여기로 온다.
  needsConsentRenewal,

  /// 학교 메일을 아직 인증하지 않았다(02 · 03). 동의 다음, 학과 앞이다 — 가입 때 한 번만 받는다.
  /// 소셜 로그인 계정의 이메일과는 별개다. 판단은 서버 `school_email_verified` 만 본다.
  /// 서버의 졸업생 인증 플래그(`graduate_enabled`)가 꺼져 있거나 옛 서버면 늘 이 값이다 — 02 에 앱바 화살표가 없다.
  needsSchoolEmail,

  /// 졸업생 인증이 켜진 서버에서 아직 인증 방법을 고르지 않았다(방법 고르기). 동의 다음, 학교 메일 앞이다.
  needsVerificationMethod,

  /// 방법 고르기에서 "학교 메일" 을 골라 02 · 03 에 왔다. 화면은 [needsSchoolEmail] 과 같지만 02 에 앱바 화살표가 있다
  /// (방법 고르기로 돌아갈 곳이 있다).
  needsSchoolEmailChosen,

  /// "졸업증명서" 를 골랐다 — 신청 폼. 반려된 뒤 다시 신청하는 폼도 같은 관문이다(횟수를 다 썼으면 폼 대신 문의 안내).
  needsGraduateApplication,

  /// 졸업증명서를 내고 심사를 기다린다. 앱바 화살표가 없다.
  graduateReviewing,
  needsSchoolInfo,
  complete;

  /// 서버 `GET /me/verification-status` 응답 한 번으로 관문을 정한다. 위젯도 네트워크도 없는 순수 규칙이다.
  ///
  /// 칸이 없으면(동의 관문 전의 옛 서버) 지금 규칙 그대로 — 없는 POST /me/consents 앞에 갇히지 않게.
  static VerificationGate fromStatus(Map<String, dynamic> fields) {
    return switch (fields['consent']) {
      'none' => needsConsent,
      'outdated' => needsConsentRenewal,
      _ => _afterConsent(fields),
    };
  }

  /// 동의 다음은 학교 메일(또는 졸업생 길), 그다음이 학과다. 학생증 칸(`status` · `reject_reason`)은 읽지 않는다 —
  /// 서버가 옛 앱 호환으로 늘 "verified" 를 내려 줄 뿐이다(2026-10-17 학생증 제거).
  /// ponytail: 칸이 없으면(학교 메일 관문 전의 옛 서버) 인증된 것으로 본다 — 서버 배포 뒤 제거 가능.
  /// `false` 일 때만 막는다. 칸이 없는데 막으면 없는 POST /school-email/verify 앞에 갇힌다.
  /// 인증을 마친 사람(학교 메일이든 졸업생 승인이든)은 졸업생 칸을 보지 않는다.
  static VerificationGate _afterConsent(Map<String, dynamic> fields) {
    if (fields['school_email_verified'] == false) {
      return _beforeIdentity(fields);
    }
    return fields['has_school_info'] as bool ? complete : needsSchoolInfo;
  }

  /// 신분 인증 전. 졸업생 인증 플래그가 `true` 가 아니면 예전 그대로 [needsSchoolEmail] 이다(서버 플래그가 꺼져 있으면
  /// 앱 흐름이 지금과 같아야 한다). 켜져 있으면 대기 → 신청(방법이 졸업증명서이거나 반려) → 학교 메일 → 방법 고르기 순이다.
  static VerificationGate _beforeIdentity(Map<String, dynamic> fields) {
    if (fields['graduate_enabled'] != true) {
      return needsSchoolEmail;
    }
    final graduate = GraduateRequestState.tryParse(fields['graduate']);
    if (graduate is GraduatePending) {
      return graduateReviewing;
    }
    if (graduate is GraduateRejected) {
      return needsGraduateApplication;
    }
    return switch (VerificationMethod.tryParse(fields['verification_method'])) {
      VerificationMethod.graduateCertificate => needsGraduateApplication,
      VerificationMethod.schoolEmail => needsSchoolEmailChosen,
      null => needsVerificationMethod,
    };
  }
}
