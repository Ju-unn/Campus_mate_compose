import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_view_model.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// 푸시 `data.route` 가 가리키는 화면의 목록을 다시 읽는다. 앱이 켜져 있을 때 받은 알림과,
/// 알림을 눌러 화면을 옮기기 직전에 같이 쓴다 — 옮기기만 하면 백그라운드 동안 낡은 목록이 그대로 남는다.
/// `ref.read` 와 `ProviderContainer.read` 를 둘 다 받는다.
void refreshForPush(T Function<T>(ProviderListenable<T>) read, Map<String, dynamic> data) {
  switch (data['route']) {
    case 'daily_card':
      unawaited(read(todayCardsViewModelProvider.notifier).refresh());
    case 'acceptances':
      unawaited(read(acceptancesViewModelProvider.notifier).refresh());
    // 매칭 성사 — 수락함에서 그 줄이 빠지고 대화 목록에 방이 생긴다. 대화 탭은 들어갈 때 다시 읽지 않는다.
    case 'match':
      unawaited(read(acceptancesViewModelProvider.notifier).refresh());
      unawaited(read(conversationsViewModelProvider.notifier).refresh());
    // 방을 열어 두고 있으면 Realtime 이 이미 줄을 붙였다 — 여기서는 목록만 맞춘다.
    case 'chat':
      unawaited(read(conversationsViewModelProvider.notifier).refresh());
    // 통과면 관문까지 다시 물어 다음 화면으로, 거절이면 3b 에 사유 배너를 띄운다.
    case 'verification':
      unawaited(read(studentVerificationViewModelProvider.notifier).refreshStatus());
  }
}

/// 앱이 켜진 채 푸시가 오면 홈 종 배지(안 읽은 알림 수)를 서버 값으로 다시 맞춘다 — 푸시 한 번에 한 번.
/// 서버가 알림함에 한 줄 남기는 일과 푸시는 같은 자리에서 일어나는데, 앱은 홈 진입 · 앱 재개 · 알림함 복귀 때만 읽어 왔다.
///
/// `data` 를 보지 않고 모든 푸시에서 읽는다: 푸시 data 에는 kind 가 없고 route 만 있는데, `route: chat` 은 알림함에 안 남는
/// 새 메시지 · 신뢰 리마인드와 남는 match_made(카톡 아이디 공개)가 함께 쓴다 — 채팅을 빼면 그 배지를 놓친다.
/// 안 남는 알림에서는 같은 수를 한 번 더 읽을 뿐이라 배지는 틀리지 않는다.
/// 로그아웃 상태와 관문이 끝나지 않은 계정은 [refreshOnResume] 과 같이 건너뛴다.
void refreshUnreadForPush(
  T Function<T>(ProviderListenable<T>) read, {
  required bool isAuthenticated,
  required VerificationGate gate,
}) {
  if (!isAuthenticated || gate != VerificationGate.complete) {
    return;
  }
  unawaited(read(unreadCountProvider.notifier).refresh());
}
