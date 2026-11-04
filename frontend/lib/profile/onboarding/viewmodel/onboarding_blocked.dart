import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 가입 단계 ViewModel 이 저장에 실패해 그 자리에 막혔다는 것을 사용 통계(`onboarding_blocked`)에 알린다.
/// 어느 단계인지는 [OnboardingStepListenable] 이 안다. 가입이 끝난 뒤 같은 ViewModel 을 쓰는 나 탭 편집의 실패는 거기서 걸러진다.
void reportOnboardingBlocked(Ref ref, Failure failure) =>
    ref.read(onboardingStepListenableProvider).blocked(onboardingBlockReasonOf(failure));

/// 저장 호출 바로 뒤에 한 줄로 단다 — 결과가 실패일 때만 알린다. 문구는 보지 않고 종류만 센다.
void reportIfOnboardingBlocked<T>(Ref ref, Result<T> result) =>
    result.when<void>(onSuccess: (_) {}, onFailure: (failure) => reportOnboardingBlocked(ref, failure));

/// 실패를 정해진 종류값 하나로 접는다. 서버 문구 · 상태 코드 · 입력값은 종류값에 들어가지 않는다.
/// 사진 올리기의 거절(서류 · 부적절 사진)은 사진 화면 ViewModel 이 따로 가른다.
OnboardingBlockReason onboardingBlockReasonOf(Failure failure) => switch (failure) {
      NetworkFailure() => OnboardingBlockReason.network,
      ServerUnavailableFailure() || UnknownFailure() => OnboardingBlockReason.server,
      RateLimitedFailure() => OnboardingBlockReason.rateLimited,
      SessionExpiredFailure() => OnboardingBlockReason.session,
      _ => OnboardingBlockReason.rejected,
    };
