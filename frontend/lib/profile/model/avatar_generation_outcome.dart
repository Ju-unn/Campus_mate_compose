/// `POST /profile-onboarding/avatar/generate` 응답 3종(Task B9 router.py 와 1:1 대응).
/// [Result]/[Failure] 와 같은 sealed + `when` 패턴을 쓴다.
sealed class AvatarGenerationOutcome {
  const AvatarGenerationOutcome();

  R when<R>({
    required R Function(String storagePath) ready,
    required R Function() failed,
    required R Function(int compensationHearts) fallback,
  });
}

final class AvatarReady extends AvatarGenerationOutcome {
  const AvatarReady(this.storagePath);

  final String storagePath;

  @override
  R when<R>({
    required R Function(String storagePath) ready,
    required R Function() failed,
    required R Function(int compensationHearts) fallback,
  }) {
    return ready(storagePath);
  }
}

final class AvatarFailed extends AvatarGenerationOutcome {
  const AvatarFailed();

  @override
  R when<R>({
    required R Function(String storagePath) ready,
    required R Function() failed,
    required R Function(int compensationHearts) fallback,
  }) {
    return failed();
  }
}

/// 5회 연속 실패 → 기본 아바타로 대체 + 보상 하트(project_slice2_decisions_2026-09-19).
final class AvatarFallback extends AvatarGenerationOutcome {
  const AvatarFallback(this.compensationHearts);

  final int compensationHearts;

  @override
  R when<R>({
    required R Function(String storagePath) ready,
    required R Function() failed,
    required R Function(int compensationHearts) fallback,
  }) {
    return fallback(compensationHearts);
  }
}
