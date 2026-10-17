import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final onboardingBackViewModelProvider = NotifierProvider<OnboardingBackViewModel, bool>(OnboardingBackViewModel.new);

/// 온보딩 화면의 뒤로가기(앱바 화살표 · 안드로이드 시스템 뒤로). 상태는 "서버 값을 읽는 중" 이다.
///
/// 이미 저장한 값을 **먼저** 읽고 나서 앞 화면으로 바꾼다 — 도착한 화면의 뷰모델이 처음 만들어질 때(build)
/// 읽힌 값을 바로 쓰게 하려는 것이다(나 탭 편집과 같은 방식, 입력칸 `initialValue` 가 늦게 오는 문제도 없다).
/// 읽기에 실패해도(인터넷 없음) 이동한다 — 같은 세션이면 메모리 값이 있고, 없는 칸은 빈 칸으로 연다.
class OnboardingBackViewModel extends Notifier<bool> {
  @override
  bool build() => false;

  /// 읽는 중에 또 누르면 무시한다 — 한 번에 한 단계만 간다.
  Future<void> goBack() async {
    final back = ref.read(onboardingStepListenableProvider).value?.stepBack();
    if (state || back == null) {
      return;
    }
    state = true;
    await _readSaved(back);
    if (!ref.mounted) {
      return;
    }
    state = false;
    ref.read(onboardingStepListenableProvider).goBack();
  }

  /// 두 provider 모두 실패를 [Result] 로 돌려줘 던지지 않는다.
  Future<void> _readSaved(OnboardingStep back) async {
    ref.invalidate(myProfileProvider);
    await ref.read(myProfileProvider.future);
    if (back != OnboardingStep.kakaoId) {
      return;
    }
    ref.invalidate(savedKakaoIdProvider);
    await ref.read(savedKakaoIdProvider.future);
  }
}
