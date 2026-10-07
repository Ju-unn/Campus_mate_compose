import 'package:campus_mate/auth/viewmodel/student_verification_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_view_model.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/core/push/push_refresh.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _Verification extends StudentVerificationViewModel {
  @override
  StudentVerificationUiState build() => const StudentVerificationUiState();

  @override
  Future<void> refreshStatus() async => _refreshed.add('verification');
}

void main() {
  late ProviderContainer container;

  setUp(() {
    _refreshed.clear();
    container = ProviderContainer(overrides: [
      todayCardsViewModelProvider.overrideWith(_Today.new),
      acceptancesViewModelProvider.overrideWith(_Acceptances.new),
      conversationsViewModelProvider.overrideWith(_Conversations.new),
      studentVerificationViewModelProvider.overrideWith(_Verification.new),
    ]);
    addTearDown(container.dispose);
  });

  List<String> refreshedBy(Map<String, dynamic> data) {
    refreshForPush(container.read, data);
    return List.of(_refreshed);
  }

  test('매칭 성사 알림은 수락함과 대화 목록을 둘 다 다시 읽는다', () {
    expect(refreshedBy({'route': 'match', 'match_id': 'm1'}), unorderedEquals(['acceptances', 'conversations']));
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

  test('학생증 검토 결과 알림은 3b 상태만 다시 읽는다', () {
    expect(refreshedBy({'route': 'verification'}), ['verification']);
  });

  test('모르는 route 와 route 없는 알림은 아무 목록도 읽지 않는다', () {
    expect(refreshedBy({'route': 'sticker'}), isEmpty);
    expect(refreshedBy(const {}), isEmpty);
  });
}
