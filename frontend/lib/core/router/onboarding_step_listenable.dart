import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter/foundation.dart';

/// 첫 조회가 실패했을 때 쓰는 비관적 기본값. 아직 아무것도 안 채운 것으로 본다.
const OnboardingStep _defaultStep = OnboardingStep.basicInfo;

/// 온보딩 다음 단계를 캐시하고, 바뀌면 go_router 재평가를 트리거한다
/// ([VerificationGateListenable]과 같은 패턴 — 검증 게이트와 온보딩은 서로 다른 자원이라 별도로 둔다).
///
/// 조회가 한 번도 끝나기 전에는 `null`(아직 모름)이라 라우터가 스플래시에 둔다. 예전에는 처음부터 04-1 이라,
/// 관문 조회가 먼저 끝나면 온보딩을 마친 사람에게도 04-1 이 몇 초 보였다가 홈으로 갔다.
///
/// 각 온보딩 화면의 ViewModel 이 저장에 성공한 순간 [refresh] 를 불러야 다음 화면으로 넘어간다.
class OnboardingStepListenable extends ChangeNotifier {
  OnboardingStepListenable(this._repository);

  final OnboardingRepository _repository;
  OnboardingStep? _cached;

  /// 아직 모르면 null.
  OnboardingStep? get value => _cached;

  /// 로그아웃 등으로 조회할 근거가 사라지면 다시 "모름" 으로 되돌린다.
  void reset() {
    _cache(null);
  }

  Future<void> refresh() async {
    final result = await _repository.fetchNextStep();
    result.when(
      onSuccess: _cache,
      // 아는 단계가 있으면 그대로 둔다 — 다음 저장 성공 때 다시 시도.
      // 모르는데 실패했으면 04-1 로 대신한다 — 스플래시에 갇히지 않게(정지 · 재동의 · 인터넷 없음은 관문이 먼저 막는다).
      onFailure: (_) {
        if (_cached == null) {
          _cache(_defaultStep);
        }
      },
    );
  }

  void _cache(OnboardingStep? step) {
    if (step == _cached) {
      return;
    }
    _cached = step;
    notifyListeners();
  }
}
