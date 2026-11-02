/// 앱을 계속 써도 되는지에 대한 판정. 시작 화면이 이 값으로 "업데이트해 주세요" 안내로 막을지 정한다.
sealed class UpdateRequirement {
  const UpdateRequirement();
}

/// 막지 않는다. 서버가 최소 버전을 안 정했거나, 이미 그 이상이거나, **판정을 못 한 모든 경우**(서버 장애 · 시간 초과 ·
/// 이상한 응답 · 버전을 못 읽음)도 여기다 — 장애 때 앱이 잠기지 않게 한다.
final class UpdateNotRequired extends UpdateRequirement {
  const UpdateNotRequired();
}

/// 서버가 정한 최소 버전보다 낮다. 안내 화면이 [storeUrl](구글 플레이 또는 앱 스토어 상세)로 스토어를 연다.
final class UpdateRequired extends UpdateRequirement {
  const UpdateRequired(this.storeUrl);

  final String storeUrl;
}
