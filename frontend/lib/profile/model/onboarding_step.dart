/// 서버(`GET /profile-onboarding/next-step`)가 계산해 알려주는 온보딩 다음 단계.
/// 화면 04-1~06-3 순서(DESIGN.md §9)를 그대로 따른다.
enum OnboardingStep {
  basicInfo,
  kakaoId,
  photos,
  avatar,
  appearanceType,
  interests,
  myTraits,
  survey,
  idealConditions,
  idealTraits,
  idealNote,
  bio,
  complete;

  static OnboardingStep fromWire(String value) => switch (value) {
        'basic_info' => basicInfo,
        'kakao_id' => kakaoId,
        'photos' => photos,
        'avatar' => avatar,
        'appearance_type' => appearanceType,
        'interests' => interests,
        'my_traits' => myTraits,
        'survey' => survey,
        'ideal_conditions' => idealConditions,
        'ideal_traits' => idealTraits,
        'ideal_note' => idealNote,
        'bio' => bio,
        _ => complete,
      };
}
