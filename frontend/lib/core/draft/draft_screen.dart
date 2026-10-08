/// 입력 중인 값을 폰에 임시 저장하는 온보딩 화면. [key] 가 저장 키의 마지막 칸이다
/// (`onboarding_draft/{계정 id}/{화면 키}`).
///
/// 온보딩 12단계 중 두 단계는 **일부러 없다.** 여기 없는 화면은 저장할 방법 자체가 없다.
/// - 카카오톡 아이디(04-1b): 평문으로 폰에 남기지 않는다(2026-10-08 사용자 결정). 같은 이유로 기본 정보의 전화번호도 빼고 저장한다.
/// - 아바타 만들기: 서버가 작업 상태를 들고 있어 앱이 따로 남길 값이 없다.
enum DraftScreen {
  basicInfo('basic_info'),
  photos('photos'),
  appearanceType('appearance_type'),
  interests('interests'),
  myTraits('my_traits'),
  survey('survey'),
  idealConditions('ideal_conditions'),
  idealTraits('ideal_traits'),
  idealNote('ideal_note'),
  bio('bio');

  const DraftScreen(this.key);

  final String key;
}
