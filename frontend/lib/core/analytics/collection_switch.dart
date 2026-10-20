/// 약관 동의 전에는 꺼 두고, 동의 뒤에만 켜는 수집 도구(사용 통계 · 오류 수집 · 성능 측정)가 공통으로 가진 두 동작.
/// 켜고 끄는 때는 [CollectionConsent] 가 정한다.
abstract interface class CollectionSwitch {
  /// 약관 동의를 마친 뒤 수집을 켠다. 여러 번 불러도 같다.
  void enableAfterConsent();

  /// 수집을 끈다(로그아웃 · 탈퇴 · 약관 재동의 전).
  void disable();
}
