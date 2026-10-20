import 'package:campus_mate/core/analytics/analytics_service.dart';
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
/// 각 온보딩 화면의 ViewModel 이 저장에 성공한 순간 [stepSaved] 를 불러야 다음 화면으로 넘어간다.
///
/// 온보딩 뒤로가기(계획서 가-2): 서버 단계(가장 멀리 간 곳)는 그대로 두고 "다시 보는 단계" 하나를 앞에 얹는다.
/// 라우터는 [value] 화면에 사람을 묶으니 앞 화면으로만 갈 수 있고, 서버 단계 너머로는 못 간다.
/// 다시 보는 단계는 메모리에만 있다 — 앱을 다시 켜면 서버 단계에서 시작한다.
class OnboardingStepListenable extends ChangeNotifier {
  OnboardingStepListenable(this._repository, {this._analytics = const NoAnalyticsService()});

  final OnboardingRepository _repository;
  final AnalyticsService _analytics;
  OnboardingStep? _cached;

  /// 뒤로가기로 돌아가 다시 보고 있는 앞 단계. 늘 [_cached] 보다 앞이다. 다시 보는 중이 아니면 null.
  OnboardingStep? _visiting;

  /// 라우터가 묶는 단계. 아직 모르면 null.
  OnboardingStep? get value => _visiting ?? _cached;

  /// 서버 단계보다 앞 화면을 다시 보고 있는가 — 화면이 서버 값으로 칸을 채울지 정한다.
  bool get isRevisiting => _visiting != null;

  /// 지금 화면에서 뒤로 갈 앞 단계가 있는가(04-1 · 04-4 는 없다, [OnboardingStep.stepBack]).
  bool get canGoBack => value?.stepBack() != null;

  /// 한 단계 앞 화면으로 돌아간다. 갈 곳이 없으면 아무것도 하지 않는다.
  void goBack() {
    final back = value?.stepBack();
    if (back == null) {
      return;
    }
    _visiting = back;
    notifyListeners();
  }

  /// 화면이 저장에 성공했을 때 부른다. 다시 보는 중이면 바로 다음 화면으로 한 칸 가고(사용자 결정 ③),
  /// 그 칸이 서버 단계에 닿으면 다시 보기를 끝낸다. 그다음 서버 단계를 다시 묻는다.
  /// [refresh] 와 따로 두는 이유: refresh 는 토큰 갱신 때마다 돈다(main.dart) — 거기서 한 칸씩 가면 화면이 혼자 넘어간다.
  Future<void> stepSaved() async {
    if (_visiting case final visiting?) {
      _visiting = _visibleBeforeServer(visiting.stepAfter());
      notifyListeners();
    }
    await refresh();
  }

  /// 로그아웃 등으로 조회할 근거가 사라지면 다시 "모름" 으로 되돌린다. 다음 계정이 다시 보기를 물려받지 않게 함께 지운다.
  void reset() {
    _visiting = null;
    _cache(null);
  }

  /// 서버 단계를 다시 묻는다. 다시 보는 단계는 건드리지 않는다(서버 단계에 닿았을 때만 끝난다, [_cache]).
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
    _logIfOnboardingFinished(step);
    _cached = step;
    // 서버 단계가 다시 보는 단계와 같거나 앞으로 바뀌면 다시 보기를 끝낸다 — 서버 단계 너머 화면에 머물지 않게.
    _visiting = _visibleBeforeServer(_visiting);
    notifyListeners();
  }

  /// 가입 중이던 단계(이미 한 번 조회해 안다)에서 complete 가 된 순간만 사용 통계에 남긴다.
  /// 앱을 켰더니 이미 complete 인 기존 사용자(첫 조회, 이전 값 null)는 가입을 방금 끝낸 것이 아니라서 세지 않는다.
  void _logIfOnboardingFinished(OnboardingStep? step) {
    if (step == OnboardingStep.complete && _cached != null) {
      _analytics.logOnboardingComplete();
    }
  }

  /// 서버 단계보다 앞일 때만 다시 보는 단계로 남긴다.
  OnboardingStep? _visibleBeforeServer(OnboardingStep? step) {
    final server = _cached;
    if (step == null || server == null || !step.isBefore(server)) {
      return null;
    }
    return step;
  }
}
