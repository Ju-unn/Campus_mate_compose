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

  /// 04-3 아바타 사진 고르기. 서버 단계로는 여전히 `photos` 라 04-2 아래 경로에 둔다.
  static const String onboardingAvatarSource = '/onboarding/photos/avatar-source';
  static const String onboardingAvatar = '/onboarding/avatar';
  static const String onboardingAppearanceType = '/onboarding/appearance-type';
  static const String onboardingInterests = '/onboarding/interests';
  static const String onboardingMyTraits = '/onboarding/my-traits';
  static const String onboardingSurvey = '/onboarding/survey';
  static const String onboardingIdealConditions = '/onboarding/ideal-conditions';
  static const String onboardingIdealTraits = '/onboarding/ideal-traits';
  static const String onboardingIdealNote = '/onboarding/ideal-note';
  static const String onboardingBio = '/onboarding/bio';

  /// 조각 4 — 오늘의 카드(화면 10), 카드 상세(10b), 매칭 성사(12), 대화(13), 설정(16)·알림(16d)
  static const String today = '/today';
  static const String cardDetail = '/cards'; // `/cards/:cardId`
  static const String matchMade = '/match-made';
  static const String conversations = '/conversations';
  static const String settings = '/settings';
  static const String notificationSettings = '/settings/notifications';

  /// 조각 5 — 채팅방(화면 14). `/chat/:matchId`
  static const String chatRoom = '/chat';

  /// 아직 화면이 없는 탭 — 자리 화면으로 보낸다(커뮤니티 조각 6, 내 프로필 후속)
  static const String community = '/community';
  static const String communityNew = '/community/new';
  static const String communityPoll = '/community/polls'; // `/community/polls/:pollId`
  static const String myProfile = '/me';
}
