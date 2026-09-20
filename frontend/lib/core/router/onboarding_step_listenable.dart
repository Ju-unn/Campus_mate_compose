import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter/foundation.dart';

/// 조회 결과가 없을 때 쓰는 비관적 기본값. 아직 아무것도 안 채운 것으로 본다.
const OnboardingStep _defaultStep = OnboardingStep.basicInfo;

/// 온보딩 다음 단계를 캐시하고, 바뀌면 go_router 재평가를 트리거한다
/// ([VerificationGateListenable]과 같은 패턴 — 검증 게이트와 온보딩은 서로 다른 자원이라 별도로 둔다).
///
/// 각 온보딩 화면의 ViewModel 이 저장에 성공한 순간 [refresh] 를 불러야 다음 화면으로 넘어간다.
class OnboardingStepListenable extends ChangeNotifier {
  OnboardingStepListenable(this._repository);

  final OnboardingRepository _repository;
  OnboardingStep _cached = _defaultStep;

  OnboardingStep get value => _cached;

  /// 로그아웃 등으로 조회할 근거가 사라지면 기본값으로 되돌린다.
  void reset() {
    _cache(_defaultStep);
  }

  Future<void> refresh() async {
    final result = await _repository.fetchNextStep();
    result.when(
      onSuccess: _cache,
      onFailure: (_) {}, // 실패하면 캐시를 유지한다 — 다음 저장 성공 때 다시 시도
    );
  }

  void _cache(OnboardingStep step) {
    if (step == _cached) {
      return;
    }
    _cached = step;
    notifyListeners();
  }
}
