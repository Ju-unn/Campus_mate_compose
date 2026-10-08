import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/result.dart';

/// 학교 메일 1회 인증(02 · 03). 소셜 로그인 뒤, 약관 동의 다음 관문이다.
///
/// 인증번호를 받고 확인하는 일은 메인(소셜) 연결과 따로 둔 **임시 연결**이 하고, 끝나면 그 임시 토큰을
/// 메인 연결로 인증한 서버 API 에 실어 보낸다. 임시 이메일 계정은 서버가 지운다 — 앱은 지우지 않는다(권한 없음).
abstract interface class SchoolEmailRepository {
  /// 임시 연결로 학교 메일에 인증번호를 보낸다. 등록되지 않은 도메인 · 재가입 제한은 가입 직전 훅이 여기서 거절한다.
  Future<Result<void>> requestCode(UniversityEmail email);

  /// 임시 연결로 인증번호를 확인하고 임시 세션의 access_token 을 돌려준다. 저장하지 않는다.
  Future<Result<String>> verifyCode(UniversityEmail email, VerificationCode code);

  /// 임시 토큰을 서버(POST /school-email/verify)에 넘겨 인증을 마친다. 끝나면 성공이든 실패든 임시 연결을 비운다.
  /// 이미 인증이 끝난 계정이면 성공으로 본다 — 게이트를 다시 읽으면 다음 단계로 간다.
  Future<Result<void>> complete(String temporaryAccessToken);
}
