import 'dart:async';

import 'package:campus_mate/auth/gate/model/data/verification_gate.dart';
import 'package:campus_mate/billing/store/viewmodel/heart_purchase_view_model.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/rejected_cards_view_model.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase, ProviderListenable;

/// 앱이 백그라운드에서 돌아왔을 때(앱 루트가 부른다) 하단 내비 "대화" 숫자의 재료인
/// 수락 대기와 대화 목록(그리고 홈 종 배지의 안 읽은 알림 수)을 **조용히** 다시 읽는다 — 어느 탭에 있든 숫자가 낡지 않게.
/// 하트 결제도 여기서 복구한다 — 결제 창(구글 플레이 화면)에서 돌아오거나, 지급이 늦어진 결제를 앱을 다시 열 때 이어서 받는다.
///
/// 로그아웃 상태와, 관문이 끝나지 않은 계정(대화 조회가 403 일 수 있다)은 건너뛴다 —
/// 건너뛰는 동안에는 아직 안 만들어진 provider 를 여기서 처음 만들지도 않는다.
/// 읽는 중이면 뷰모델의 `_inFlight` 가드가 겹침을 막는다. `ref.read` 와 `ProviderContainer.read` 를 둘 다 받는다.
///
/// [fromBackground] 가 false 면(inactive 만 거친 복귀 — 알림 센터 · 시스템 창 · 결제 창) 하트 결제만 복구한다.
/// 앱이 화면에서 사라진 적이 없어 사용자 채널이 그대로 붙어 있으니 목록 · 숫자는 낡지 않았다(1.0.7 #6).
void refreshOnResume(
  T Function<T>(ProviderListenable<T>) read,
  bool Function(ProviderBase<Object?>) exists, {
  required bool isAuthenticated,
  required VerificationGate gate,
  bool fromBackground = true,
}) {
  if (!isAuthenticated || gate != VerificationGate.complete) {
    return;
  }
  // 결제 창(구글 플레이 · 애플)이 바로 inactive 만 거치는 경우다 — 늦게 온 결제는 매번 이어 받는다.
  unawaited(read(heartPurchaseViewModelProvider.notifier).refresh());
  if (fromBackground) {
    _refreshLists(read, exists);
  }
}

/// 백그라운드에서 돌아왔을 때만 — 수락 대기 · 보낸 신청 · 거절한 카드 · 대화 목록 · 안 읽은 알림 수를 조용히 다시 읽는다.
void _refreshLists(T Function<T>(ProviderListenable<T>) read, bool Function(ProviderBase<Object?>) exists) {
  unawaited(read(acceptancesViewModelProvider.notifier).refresh(quiet: true));
  // 보낸 신청은 숫자 재료가 아니지만 대화 탭을 보던 중이면 매칭된 신청이 "기다리는 중" 으로 남는다(대화 중에는 방이 보이는데).
  unawaited(read(sentRequestsViewModelProvider.notifier).refresh(quiet: true));
  // 거절한 카드는 7일이 지나면 서버가 뺀다 — 카드 대기 입구가 낡지 않게. 읽은 적이 없으면 건드리지 않는다.
  refreshRejectedCardsIfRead(read, exists);
  unawaited(read(conversationsViewModelProvider.notifier).refresh(quiet: true));
  unawaited(read(unreadCountProvider.notifier).refresh());
}
