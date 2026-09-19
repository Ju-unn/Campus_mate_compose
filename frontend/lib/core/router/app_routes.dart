/// 앱의 화면 경로.
/// 문자열을 화면마다 적지 않고 여기서만 관리한다.
abstract final class AppRoutes {
  /// 앱 진입 직후의 대기 화면
  static const String splash = '/';

  /// 로그인·가입 화면
  static const String login = '/login';

  /// 인증코드 입력 화면 (로그인 화면에서 이메일과 함께 이동)
  static const String verifyCode = '/verify-code';

  /// 학생증 사진·실명 제출 화면 (화면 3b)
  static const String studentVerification = '/student-verification';

  /// 학과·학번 입력 화면 (화면 3c)
  static const String schoolInfo = '/school-info';

  /// 로그인 후 첫 화면
  static const String home = '/home';
}
