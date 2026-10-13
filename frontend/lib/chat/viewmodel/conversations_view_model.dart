import 'dart:async';

import 'package:campus_mate/chat/model/chat_errors.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/chat/model/user_event_stream.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final conversationsViewModelProvider =
    NotifierProvider<ConversationsViewModel, ConversationsUiState>(ConversationsViewModel.new);

/// 대화 중 목록(화면 13 아래 섹션). 방마다 채널을 열지 않고, 앱이 앞에 있는 동안 듣는 **사용자 채널** 하나
/// (`user:<내 id>`, 설계안 A — `user_channel.dart`)가 새 줄을 [applyMessage] 로 바로 넣는다. 푸시 · 당겨서 새로고침에 더해,
/// 대화 탭 화면이 떠 있는 동안은 화면의 타이머가 `refresh(quiet: true)` 를 부른다(`conversations_screen.dart`, 채널이
/// 붙었으면 30초 · 아니면 3초) — 타이머는 화면이 쥐고 이 뷰모델은 모른다. 값의 기준은 서버 읽기다.
class ConversationsViewModel extends Notifier<ConversationsUiState> {
  Future<void>? _inFlight;

  /// 진행 중인 읽기에 조용하지 않은 호출이 합쳐졌다. 그 읽기는 호출보다 먼저 시작됐으니(낡았을 수 있고,
  /// 실패해도 오류를 안 보인다) 끝난 뒤 조용하지 않게 한 번 더 읽는다. 합쳐진 호출이 몇 번이든 한 번이다.
  bool _readAgain = false;

  /// 진행 중인 읽기 도중 실시간 줄이 왔거나 사용자 채널이 붙었다. 그 읽기는 그보다 먼저 서버를 봤을 수 있어 결과가 방금 넣은 줄을
  /// 덮거나 놓친다 — 끝난 뒤 **조용히** 한 번 더 읽어 서버 값으로 맞춘다(사용자가 누른 일이 아니라 실패해도 오류 줄을 띄우지 않는다).
  bool _readAgainQuietly = false;

  @override
  ConversationsUiState build() {
    // 첫 읽기는 isLoading 이라 quiet 여도 실패를 보인다. quiet 로 불러야 화면 initState 의 조용한 읽기와
    // 합쳐질 때 다시 읽기가 생기지 않는다.
    Future.microtask(() => refresh(quiet: true));
    return const ConversationsUiState();
  }

  /// [quiet] 은 앱 복귀·화면 진입 때 자동으로 읽는 경우다 — 실패해도 이미 보이는 줄을 그대로 두고
  /// 오류 줄을 새로 띄우지 않는다. 사용자가 당겨서 새로고침하거나 푸시로 읽을 때는 오류를 보인다.
  /// 읽는 중에 불리면 그 읽기에 합쳐지고, 조용하지 않은 호출이면 끝난 뒤 한 번 더 읽은 다음에 완료된다.
  Future<void> refresh({bool quiet = false}) {
    final running = _inFlight;
    if (running == null) {
      return _inFlight = _loadAndRepeat(quiet).whenComplete(() => _inFlight = null);
    }
    _readAgain = _readAgain || !quiet;
    return running;
  }

  Future<void> _loadAndRepeat(bool quiet) async {
    await _load(quiet: quiet);
    while (_readAgain || _readAgainQuietly) {
      final loud = _readAgain;
      _readAgain = false;
      _readAgainQuietly = false;
      await _load(quiet: !loud);
    }
  }

  /// 사용자 채널이 (다시) 붙었거나 방이 바뀌었다 — 조용히 읽는다. **읽는 중이면 겹쳐 부르지 않되 끝난 뒤 한 번 더 읽는다**:
  /// 그 읽기(앱 복귀 읽기 등)는 채널이 붙기 전의 서버를 봤을 수 있어, 그 사이 들어온 줄이 읽기에도 이벤트에도 없다.
  void catchUp() {
    if (_inFlight != null) {
      _readAgainQuietly = true;
      return;
    }
    unawaited(refresh(quiet: true));
  }

  /// 사용자 채널로 온 새 줄(설계안 A)을 서버를 다시 읽지 않고 바로 반영한다 — 마지막 줄 · 시각 · 안 읽은 수, 그 방을 위로.
  /// 내가(다른 기기에서) 보낸 줄과 사용자가 지금 보고 있는 방([seen])의 줄은 안 읽은 수를 올리지 않는다.
  /// 같은 줄이 두 번 와도 · 서버 목록이 이미 센 줄이 와도 [Conversation.receive] 가 한 번만 센다. 목록에 없는 방이면 다시 읽는다.
  void applyMessage(MessageEvent event, {required String myId, required bool seen}) {
    if (_inFlight != null) {
      _readAgainQuietly = true;
    }
    final index = state.conversations.indexWhere((conversation) => conversation.matchId == event.matchId);
    if (index < 0) {
      unawaited(refresh(quiet: true));
      return;
    }
    final message = event.message;
    final current = state.conversations[index];
    final updated = current.receive(message, unread: message.senderId != myId && !seen);
    if (!identical(updated, current)) {
      state = state.copyWith(conversations: _placed(updated), errorMessage: state.errorMessage);
    }
  }

  /// [updated] 를 서버와 같은 순서(마지막 줄 시각 내림차순) 자리에 다시 세운다.
  List<Conversation> _placed(Conversation updated) {
    final others = [for (final c in state.conversations) if (c.matchId != updated.matchId) c];
    final at = others.indexWhere((c) => !c.lastMessageAt.isAfter(updated.lastMessageAt));
    return others..insert(at < 0 ? others.length : at, updated);
  }

  Future<void> _load({required bool quiet}) async {
    final result = await ref.read(chatRepositoryProvider).fetchConversations();
    state = result.when(
      onSuccess: (conversations) =>
          state.copyWith(isLoading: false, conversations: conversations),
      // 첫 읽기(isLoading)는 quiet 여도 스켈레톤을 끝내야 한다 — build() 의 첫 읽기와 합쳐지는 경우도 같다.
      onFailure: (failure) => quiet && !state.isLoading
          ? state
          : state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 13a 밀어서 나가기(결정 10). 방 안 나가기와 같은 호출이다 — 나가면(이미 나갔어도) 그 줄을 빼고,
  /// 실패면 줄은 두고 목록 위 오류 줄로 알린다.
  Future<void> leave(String matchId) async {
    final result = await ref.read(chatRepositoryProvider).leave(matchId);
    state = result.when(
      onSuccess: (_) => _without(matchId),
      onFailure: (failure) => isAlreadyLeft(failure)
          ? _without(matchId)
          : state.copyWith(errorMessage: chatFailureMessage(failure)),
    );
  }

  ConversationsUiState _without(String matchId) => state.copyWith(
        conversations: [for (final c in state.conversations) if (c.matchId != matchId) c],
      );
}

/// 하단 내비 "대화" 탭 뱃지(DESIGN §8.8). **수락 대기 + 안 읽은 메시지의 합** —
/// 의미는 "나를 기다리는 사람 수" 하나다. 0 이면 뱃지를 그리지 않는다.
final chatBadgeCountProvider = Provider<int>((ref) {
  return ref.watch(acceptancesViewModelProvider).acceptances.length +
      ref.watch(conversationsViewModelProvider).unreadTotal;
});
