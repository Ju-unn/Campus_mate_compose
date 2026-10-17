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

  /// 서버가 단계를 세는 순서(`backend/app/profile_onboarding/onboarding_progress.py` `_STEPS`). 다시 저장한 뒤
  /// 한 칸 앞으로([stepAfter])와 서버 단계 비교([isBefore])는 이 순서로 센다 — 위 선언 순서는 avatar 자리가 달라 쓰지 않는다.
  /// 10-17 아바타 리빌 맨 끝 결정으로 avatar 는 bio 뒤다. 서버가 아직 옛 순서(survey 뒤)여도 맞게 돈다 —
  /// avatar 는 뒤로가 없어 다시 보는 일이 없고, 설문을 다시 저장하면 05-12 를 다시 보이지 않고 06-1 로 간다.
  static const List<OnboardingStep> _serverOrder = [
    basicInfo, kakaoId, photos, appearanceType, interests, myTraits, survey,
    idealConditions, idealTraits, idealNote, bio, avatar, complete,
  ];

  /// 다시 볼 수 있는 앞 단계. 없으면 null.
  /// 04-1 앞은 인증이 끝난 관문이다(사용자 결정 ⑦). 04-4 앞(사진)은 04-3 "다음" 에서 아바타가 이미 등록돼
  /// 출시 뒤로 미뤘다(사용자 결정 ①, 사진 경계). 아바타 확인(05-12)은 가입 맨 끝이라 뒤로가 없다(10-17).
  OnboardingStep? stepBack() => switch (this) {
        basicInfo || appearanceType || avatar || complete => null,
        kakaoId => basicInfo,
        photos => kakaoId,
        interests => appearanceType,
        myTraits => interests,
        survey => myTraits,
        idealConditions => survey,
        idealTraits => idealConditions,
        idealNote => idealTraits,
        bio => idealNote,
      };

  /// 서버 순서의 다음 단계. 끝 다음은 없다.
  OnboardingStep? stepAfter() => this == complete ? null : _serverOrder[_serverIndex + 1];

  /// 서버 순서로 [other] 보다 앞인가. 같은 단계는 앞이 아니다.
  bool isBefore(OnboardingStep other) => _serverIndex < other._serverIndex;

  int get _serverIndex => _serverOrder.indexOf(this);

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
