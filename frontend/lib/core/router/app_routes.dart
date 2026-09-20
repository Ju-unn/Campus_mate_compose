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

  /// 조각 2 온보딩 화면(04-1~06-3). 순서는 DESIGN.md §9, 서버 `next-step` 응답과 1:1 대응.
  static const String onboardingBasicInfo = '/onboarding/basic-info';
  static const String onboardingKakaoId = '/onboarding/kakao-id';
  static const String onboardingPhotos = '/onboarding/photos';
  static const String onboardingAvatar = '/onboarding/avatar';
  static const String onboardingAppearanceType = '/onboarding/appearance-type';
  static const String onboardingInterests = '/onboarding/interests';
  static const String onboardingMyTraits = '/onboarding/my-traits';
  static const String onboardingSurvey = '/onboarding/survey';
  static const String onboardingIdealConditions = '/onboarding/ideal-conditions';
  static const String onboardingIdealTraits = '/onboarding/ideal-traits';
  static const String onboardingIdealNote = '/onboarding/ideal-note';
  static const String onboardingBio = '/onboarding/bio';
}
