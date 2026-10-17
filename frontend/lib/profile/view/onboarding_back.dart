import 'dart:async';

import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/viewmodel/onboarding_back_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 온보딩 화면의 뒤로 함수 — 앱바 화살표(`OnboardingAppBar.onBack`)와 안드로이드 시스템 뒤로(`BackExitScope.onBack`)에
/// **같은 함수**를 준다. 앞 단계가 없으면(04-1 · 04-4) null — 화살표가 없고 시스템 뒤로는 종료 안내다.
/// [isBusy](저장 중)면 눌러도 아무 일이 없다 — 저장 뒤 한 칸 넘김이 엉뚱한 단계에서 일어나지 않게.
/// 화살표는 숨기지 않는다(숨기면 깜빡인다).
VoidCallback? onboardingBack(WidgetRef ref, {required bool isBusy}) {
  final steps = ref.read(onboardingStepListenableProvider);
  if (!steps.canGoBack) {
    return null;
  }
  if (isBusy) {
    return () {};
  }
  final shown = steps.value;
  return () {
    // 읽기가 끝나 단계는 이미 앞으로 바뀌었는데 화면은 다음 프레임에 바뀐다 — 그 틈에 또 누르면 한 칸 더 가지 않게.
    if (steps.value != shown) {
      return;
    }
    unawaited(ref.read(onboardingBackViewModelProvider.notifier).goBack());
  };
}
