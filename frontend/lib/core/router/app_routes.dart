/// 앱의 화면 경로.
/// 문자열을 화면마다 적지 않고 여기서만 관리한다.
abstract final class AppRoutes {
  /// 앱 진입 직후의 대기 화면
  static const String splash = '/';

  /// 로그인·가입 화면
  static const String login = '/login';

  /// 인증코드 입력 화면 (로그인 화면에서 이메일과 함께 이동)
  static const String verifyCode = '/verify-code';

  /// 약관 동의 화면(화면 02-c · 재동의 02-c-4). 로그인 직후 첫 관문이다.
  static const String consent = '/consent';

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

  /// 20 추천 코드 · 20d 유입경로. 06-3 뒤 앱에서만 잇는다(서버 next-step 단계 아님, 2026-09-28 대장 D2).
  static const String onboardingReferral = '/onboarding/referral';
  static const String onboardingAcquisition = '/onboarding/acquisition';

  /// 조각 4 — 오늘의 카드(화면 10), 카드 상세(10b), 매칭 성사(12), 대화(13), 설정(16)·알림(16d)
  static const String today = '/today';
  static const String cardDetail = '/cards'; // `/cards/:cardId`
  static const String matchMade = '/match-made';
  static const String conversations = '/conversations';
  static const String settings = '/settings';
  static const String notificationSettings = '/settings/notifications';

  /// 조각 6 A6 — 16e-1 카카오톡 아이디 변경(pen `bWrnD`). 16e 계정 줄과 14f "변경" 이 연다(flat 경로, 프로필탭 합의).
  static const String kakaoIdSettings = '/settings/account/kakao-id';

  /// 조각 5 — 채팅방(화면 14). `/chat/:matchId`
  static const String chatRoom = '/chat';

  /// 조각 6 — 차단 목록(화면 16f), 상대 프로필 상세(14c). `/profiles/:profileId`
  static const String blockList = '/settings/blocks';
  static const String partnerProfile = '/profiles';

  /// 조각 6 — 연락처(지인) 차단 관리(화면 16b)와 차단할 연락처 선택(8d)
  static const String contactBlocks = '/settings/contact-blocks';
  static const String contactPicker = '/settings/contact-blocks/pick';

  /// 조각 6 A4 — 정지 안내(pen `e7QaDh`). 정지된 계정은 어느 화면에서든 여기로 간다.
  static const String accountSuspended = '/account-suspended';

  /// 16e 계정(설정 "계정" 줄에서 들어간다).
  static const String account = '/settings/account';

  /// 21 자주 묻는 질문(설정 "자주 묻는 질문" 줄이 연다, 계획서 2026-09-29-faq.md).
  static const String faq = '/settings/faq';
  /// 지인 리뷰 — 20c 받은 리뷰, 20e 내가 쓴 리뷰, 20b 리뷰 쓰기(`/home/friend-reviews/write/:profileId` — 푸시로 와도 홈 위에 시트)
  static const String friendReviews = '/friend-reviews';
  static const String friendReviewsWritten = '/friend-reviews/written';
  static const String friendReviewWrite = '/home/friend-reviews/write';

  /// 아직 화면이 없는 탭 — 자리 화면으로 보낸다(커뮤니티 조각 6, 내 프로필 후속)
  static const String community = '/community';
  static const String communityNew = '/community/new';
  static const String communityPoll = '/community/polls'; // `/community/polls/:pollId`
  static const String myProfile = '/me';

  /// 나 탭 편집(계획서 2026-09-27-me-edit.md) — 15c 자기소개·태그, 그리고 온보딩 화면을 편집 모드로 다시 띄우는 자리.
  /// `/onboarding/...` 은 완료한 사람을 홈으로 돌려보내므로(AuthRedirect) 경로를 따로 둔다.
  static const String myProfileEdit = '/me/edit';
  static const String myIdealConditions = '/me/ideal-conditions';
  static const String myTags = '/me/edit/tags'; // `/me/edit/tags/:kind` — TagPickerKind.endpoint

  /// 무료로 하트 모으기 — 18a 목록, 18b 인증샷 제출(`/heart-tasks/submit/:task`, 반려 뒤면 `?reason=`), 18c 검수 대기
  static const String heartTasks = '/heart-tasks';
  static const String heartTaskSubmit = '/heart-tasks/submit';
  static const String heartTaskPending = '/heart-tasks/pending';

  /// 화면 15 개편(계획서 2026-09-28-me-profile.md) — 15 의 입구 "프로필 편집"(`sC8BR`)이 여는 15-5(`rrJ27`).
  static const String myProfileManage = '/me/manage';

  /// 화면 15 입구 "남이 보는 내 프로필 카드"(`k3r5C`)가 여는 15-4(`gnEwq`) — 상대에게 보이는 내 카드 미리보기.
  static const String myCardPreview = '/me/preview';

  /// 15-5 "실제 사진 교체"(`E7Cv2`)가 여는 15-7 사진 수정(`szJ79`, 계획서 2026-09-28-me-profile.md A15).
  static const String myPhotos = '/me/photos';

  /// 15-5 "수정 ›"(`A8LX2`)이 여는 15-6 기본 정보 수정(`mhdYA`, 계획서 2026-09-28-me-profile.md A16) — 닉네임 · 키.
  static const String myBasicInfo = '/me/basic-info';
}
