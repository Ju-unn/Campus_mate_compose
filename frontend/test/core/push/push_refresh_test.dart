import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/core/push/push_refresh.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_verification_gate_repository.dart';
import '../../billing/model/fake_heart_task_repository.dart';
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
  late FakeVerificationGateRepository gateRepository;

  setUp(() {
    _refreshed.clear();
    gateRepository = FakeVerificationGateRepository();
    container = ProviderContainer(overrides: [
      verificationGateRepositoryProvider.overrideWithValue(gateRepository),
      todayCardsViewModelProvider.overrideWith(_Today.new),
      acceptancesViewModelProvider.overrideWith(_Acceptances.new),
      conversationsViewModelProvider.overrideWith(_Conversations.new),
      sentRequestsViewModelProvider.overrideWith(_Sent.new),
    ]);
    addTearDown(container.dispose);
  });

  List<String> refreshedBy(Map<String, dynamic> data) {
    refreshForPush(container.read, data, invalidate: container.invalidate);
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

  // 10-18 인증샷 결과 알림: 18a 를 이미 보고 있을 때 도착하면 목록과 하트 잔액이 새로 읽힌다.
  group('인증샷 결과 알림', () {
    late FakeHeartTaskRepository heartTasks;
    late int profileReads;
    late ProviderContainer heartContainer;

    setUp(() {
      heartTasks = FakeHeartTaskRepository();
      profileReads = 0;
      heartContainer = ProviderContainer(overrides: [
        heartTaskRepositoryProvider.overrideWithValue(heartTasks),
        myProfileProvider.overrideWith((ref) {
          profileReads++;
          return Completer<Result<MyProfile>>().future;
        }),
      ]);
      addTearDown(heartContainer.dispose);
    });

    /// 18a 가 열려 있는 것처럼 두 provider 를 듣고 있게 한다(첫 읽기까지 마친 상태).
    Future<void> openHeartTasksScreen() async {
      heartContainer.listen(heartTasksViewModelProvider, (_, _) {});
      heartContainer.listen(myProfileProvider, (_, _) {});
      await pumpEventQueue();
      expect((heartTasks.fetchCount, profileReads), (1, 1));
    }

    for (final route in ['heart_tasks', 'heart_task_retry']) {
      test('$route 알림이 오면 열려 있는 18a 목록과 하트 잔액을 다시 읽는다', () async {
        await openHeartTasksScreen();

        refreshForPush(heartContainer.read, {'route': route, 'task': 'everytime_post'},
            invalidate: heartContainer.invalidate);
        await pumpEventQueue();

        expect(heartTasks.fetchCount, 2);
        expect(profileReads, 2);
      });
    }

    test('18a 가 열려 있지 않으면 목록을 읽으러 가지 않는다 — 들어올 때 어차피 새로 읽는다', () async {
      refreshForPush(heartContainer.read, {'route': 'heart_tasks'}, invalidate: heartContainer.invalidate);
      await pumpEventQueue();

      expect(heartTasks.fetchCount, 0);
    });

    test('다른 알림은 18a 목록 · 하트 잔액을 건드리지 않는다', () async {
      await openHeartTasksScreen();

      refreshForPush(heartContainer.read, {'route': 'friend_reviews'}, invalidate: heartContainer.invalidate);
      await pumpEventQueue();

      expect((heartTasks.fetchCount, profileReads), (1, 1));
    });
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

  // 졸업생 인증 결과(승인 · 반려) — 앱은 화면을 옮기지 않고 관문만 다시 묻는다. 옮기는 일은 AuthRedirect 몫이다.
  test('졸업생 인증 결과 알림은 관문만 다시 묻고 다른 목록은 건드리지 않는다', () async {
    for (final data in [
      {'route': 'graduate_verification', 'state': 'approved'},
      {'route': 'graduate_verification', 'state': 'rejected', 'reason': 'unreadable'},
    ]) {
      expect(refreshedBy(data), isEmpty, reason: '$data');
    }
    await pumpEventQueue();

    expect(gateRepository.fetchCount, 2);
  });

  test('졸업생 인증이 아닌 알림은 관문을 다시 묻지 않는다', () async {
    refreshedBy({'route': 'daily_card'});
    await pumpEventQueue();

    expect(gateRepository.fetchCount, 0);
  });
}
