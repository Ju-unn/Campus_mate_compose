import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// 앱이 백그라운드에서 돌아왔을 때(앱 루트가 부른다) 하단 내비 "대화" 숫자의 재료인
/// 수락 대기와 대화 목록을 **조용히** 다시 읽는다 — 어느 탭에 있든 숫자가 낡지 않게.
///
/// 로그아웃 상태와, 관문이 끝나지 않은 계정(대화 조회가 403 일 수 있다)은 건너뛴다 —
/// 건너뛰는 동안에는 아직 안 만들어진 provider 를 여기서 처음 만들지도 않는다.
/// 읽는 중이면 뷰모델의 `_inFlight` 가드가 겹침을 막는다. `ref.read` 와 `ProviderContainer.read` 를 둘 다 받는다.
void refreshOnResume(
  T Function<T>(ProviderListenable<T>) read, {
  required bool isAuthenticated,
  required VerificationGate gate,
}) {
  if (!isAuthenticated || gate != VerificationGate.complete) {
    return;
  }
  unawaited(read(acceptancesViewModelProvider.notifier).refresh(quiet: true));
  unawaited(read(conversationsViewModelProvider.notifier).refresh(quiet: true));
}
