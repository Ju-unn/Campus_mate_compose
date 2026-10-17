import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 뒤로가기로 앞 화면을 다시 볼 때만 이미 저장한 내 프로필(`GET /me/profile`)을 준다. 그 밖에는 null.
/// 뒤로가기([OnboardingBackViewModel])가 화면을 바꾸기 전에 읽어 두므로 온보딩 뷰모델의 build 에서 바로 쓸 수 있다.
/// 채우는 순서는 폰 임시 저장 > 이 값 > 빈 값이다 — 같은 세션이면 뷰모델이 이미 살아 있어 이 값을 보지 않는다.
MyProfile? revisitProfile(Ref ref) {
  // 미리 읽지 않았으면 여기서 읽기를 시작하지 않는다(build 는 기다릴 수 없어 늦게 온 값은 어차피 못 쓴다).
  if (!ref.read(onboardingStepListenableProvider).isRevisiting || !ref.exists(myProfileProvider)) {
    return null;
  }
  return ref.read(myProfileProvider).value?.when<MyProfile?>(onSuccess: (profile) => profile, onFailure: (_) => null);
}
