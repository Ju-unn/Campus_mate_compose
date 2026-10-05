import 'dart:async';

import 'package:campus_mate/auth/viewmodel/student_verification_view_model.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
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
