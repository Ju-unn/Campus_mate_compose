import 'dart:async';

import 'package:campus_mate/graduate/viewmodel/method_back_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 신청 폼 · 학교 메일(02, 방법 고르기를 거쳐 온 경우)의 뒤로 함수 — 앱바 화살표와 안드로이드 시스템 뒤로
/// (`BackExitScope.onBack`)에 **같은 함수**를 준다(`onboardingBack` 과 같은 모양).
/// [isBusy](사진 올리는 중)면 눌러도 아무 일이 없다. 화살표는 숨기지 않는다(숨기면 깜빡인다).
VoidCallback methodBack(WidgetRef ref, {required bool isBusy}) {
  if (isBusy) {
    return () {};
  }
  return () => unawaited(ref.read(methodBackViewModelProvider.notifier).goBack());
}
