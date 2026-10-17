import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/core/push/push_refresh.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../notifications/model/fake_notifications_repository.dart';

/// 어느 목록이 다시 읽혔는지만 적는 장부. 저장소를 거치지 않으니 build() 의 첫 조회가 섞이지 않는다.
final List<String> _refreshed = [];

class _Today extends TodayCardsViewModel {
  @override
  TodayCardsUiState build() => const TodayCardsUiState();

  @override
  Future<void> refresh() async => _refreshed.add('today');
}

class _Acceptances extends AcceptancesViewModel {
  @override
  AcceptancesUiState build() => const AcceptancesUiState();

  @override
  Future<void> refresh({bool quiet = false}) async => _refreshed.add('acceptances');
}

class _Conversations extends ConversationsViewModel {
  @override
  ConversationsUiState build() => const ConversationsUiState();

  @override
  Future<void> refresh({bool quiet = false}) async => _refreshed.add('conversations');
}

class _Sent extends SentRequestsViewModel {
  @override
  SentRequestsUiState build() => const SentRequestsUiState();

  @override
  Future<void> refresh({bool quiet = false}) async => _refreshed.add('sent');
}

void main() {
  late ProviderContainer container;

  setUp(() {
    _refreshed.clear();
    container = ProviderContainer(overrides: [
      todayCardsViewModelProvider.overrideWith(_Today.new),
      acceptancesViewModelProvider.overrideWith(_Acceptances.new),
      conversationsViewModelProvider.overrideWith(_Conversations.new),
      sentRequestsViewModelProvider.overrideWith(_Sent.new),
    ]);
    addTearDown(container.dispose);
  });

  List<String> refreshedBy(Map<String, dynamic> data) {
    refreshForPush(container.read, data);
    return List.of(_refreshed);
  }

  test('매칭 성사 알림은 수락함 · 보낸 신청 · 대화 목록을 다시 읽는다 — 내 신청이 매칭됨으로 바뀐다', () {
    expect(refreshedBy({'route': 'match', 'match_id': 'm1'}),
        unorderedEquals(['acceptances', 'sent', 'conversations']));
  });

  test('받은 수락 알림은 수락함만 다시 읽는다 — 방은 내가 답해야 생긴다', () {
    expect(refreshedBy({'route': 'acceptances', 'card_id': 'c1'}), ['acceptances']);
  });

  test('카드 도착 알림은 오늘 카드만 다시 읽는다', () {
    expect(refreshedBy({'route': 'daily_card'}), ['today']);
  });

  test('새 메시지 알림은 대화 목록만 다시 읽는다', () {
    expect(refreshedBy({'route': 'chat', 'match_id': 'm1'}), ['conversations']);
  });

  test('모르는 route 와 route 없는 알림은 아무 목록도 읽지 않는다', () {
    expect(refreshedBy({'route': 'sticker'}), isEmpty);
    // 옛 학생증 검토 결과 알림(10-17 학생증 제거)도 모르는 값이다.
    expect(refreshedBy({'route': 'verification'}), isEmpty);
    expect(refreshedBy(const {}), isEmpty);
  });

  group('refreshUnreadForPush — 앱이 켜진 채 받은 푸시마다 종 배지를 다시 읽는다', () {
    late FakeNotificationsRepository notifications;

    setUp(() {
      notifications = FakeNotificationsRepository(unreadCount: 4);
      container = ProviderContainer(overrides: [
        notificationsRepositoryProvider.overrideWithValue(notifications),
      ]);
      addTearDown(container.dispose);
    });

    Future<void> receive({bool isAuthenticated = true, VerificationGate gate = VerificationGate.complete}) async {
      refreshUnreadForPush(container.read, isAuthenticated: isAuthenticated, gate: gate);
      await pumpEventQueue();
    }

    // 알림함에 남는 5종은 route 가 제각각이고 data 에 kind 도 없다. route 'chat' 은 안 남는 새 메시지 · 신뢰 리마인드와
    // 남는 match_made(카톡 아이디 공개)가 함께 쓴다 — 가를 수 없어 route 를 보지 않고 푸시마다 읽는다.
    test('푸시가 오면 안 읽은 알림 수를 한 번 읽어 배지를 맞춘다', () async {
      await receive();

      expect(notifications.countCalls, 1);
      expect(container.read(unreadCountProvider), 4);
    });

    test('로그아웃 상태 · 관문 미완료에서는 읽지 않는다', () async {
      await receive(isAuthenticated: false);
      for (final gate in VerificationGate.values.where((gate) => gate != VerificationGate.complete)) {
        await receive(gate: gate);
      }

      expect(notifications.countCalls, 0);
    });
  });
}
