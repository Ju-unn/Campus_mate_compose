/// 아바타 한 건의 **지금 상태**. `POST .../avatar/generate` 와 `GET .../avatar/status` 가 같은 모양으로
/// 답하고 앱은 이 하나로 읽는다(router.py `_avatar_status`). [Result]/[Failure] 와 같은 sealed + `when`.
///
/// 칸 이름은 계약이다 — 서버가 한쪽만 바꾸면 그 길에서만 캐스트가 터진다(운영 00020 무한 로딩).
sealed class AvatarGenerationOutcome {
  const AvatarGenerationOutcome();

  R when<R>({
    required R Function() pending,
    required R Function(String avatarUrl) ready,
    required R Function() failed,
    required R Function(String avatarUrl, int compensationHearts) fallback,
  });
}

/// 작업만 등록된 상태. 그림은 워커가 만드는 중이고, 결과 화면이 잠시 뒤 다시 물어본다.
final class AvatarPending extends AvatarGenerationOutcome {
  const AvatarPending();

  @override
  R when<R>({
    required R Function() pending,
    required R Function(String avatarUrl) ready,
    required R Function() failed,
    required R Function(String avatarUrl, int compensationHearts) fallback,
  }) {
    return pending();
  }
}

final class AvatarReady extends AvatarGenerationOutcome {
  const AvatarReady(this.avatarUrl);

  /// **전체 주소**다(저장 경로가 아니다) — 서버가 버킷 접두사까지 붙여서 준다.
  /// 앱에서 접두사를 붙이는 자리를 만들면 버킷을 바꿀 때 전부 깨진다.
  final String avatarUrl;

  @override
  R when<R>({
    required R Function() pending,
    required R Function(String avatarUrl) ready,
    required R Function() failed,
    required R Function(String avatarUrl, int compensationHearts) fallback,
  }) {
    return ready(avatarUrl);
  }
}

/// 실패했거나, 아직 한 번도 만든 적이 없거나(`none`). 화면은 둘을 같게 다룬다 — "다시 만들기".
final class AvatarFailed extends AvatarGenerationOutcome {
  const AvatarFailed();

  @override
  R when<R>({
    required R Function() pending,
    required R Function(String avatarUrl) ready,
    required R Function() failed,
    required R Function(String avatarUrl, int compensationHearts) fallback,
  }) {
    return failed();
  }
}

/// 5회 연속 실패 → 기본 아바타로 대체 + 보상 하트(project_slice2_decisions_2026-09-19).
/// 그림 주소도 같이 들고 있어야 보상 안내와 함께 그 그림을 띄울 수 있다.
/// 하트 수는 **서버가 준 값**이다 — 보상 액수는 서버 규칙이라 앱에 박으면 앱만 거짓말을 하게 된다.
final class AvatarFallback extends AvatarGenerationOutcome {
  const AvatarFallback(this.avatarUrl, this.compensationHearts);

  final String avatarUrl;
  final int compensationHearts;

  @override
  R when<R>({
    required R Function() pending,
    required R Function(String avatarUrl) ready,
    required R Function() failed,
    required R Function(String avatarUrl, int compensationHearts) fallback,
  }) {
    return fallback(avatarUrl, compensationHearts);
  }
}
