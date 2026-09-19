/// 앱의 화면 경로.
/// 문자열을 화면마다 적지 않고 여기서만 관리한다.
abstract final class AppRoutes {
  /// 앱 진입 직후의 대기 화면
  static const String splash = '/';

  /// 로그인·가입 화면
  static const String login = '/login';

  /// 인증코드 입력 화면 (로그인 화면에서 이메일과 함께 이동)
  static const String verifyCode = '/verify-code';

  /// 로그인 후 첫 화면
  static const String home = '/home';
}
