import 'package:campus_mate/chat/model/chat_errors.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final conversationsViewModelProvider =
    NotifierProvider<ConversationsViewModel, ConversationsUiState>(ConversationsViewModel.new);

/// 대화 중 목록(화면 13 아래 섹션). **목록은 실시간 구독을 쓰지 않는다** —
/// 푸시와 당겨서 새로고침으로 충분하고, 방을 안 열었는데 채널을 열어 둘 이유가 없다.
class ConversationsViewModel extends Notifier<ConversationsUiState> {
  Future<void>? _inFlight;

  /// 진행 중인 읽기에 조용하지 않은 호출이 합쳐졌다. 그 읽기는 호출보다 먼저 시작됐으니(낡았을 수 있고,
  /// 실패해도 오류를 안 보인다) 끝난 뒤 조용하지 않게 한 번 더 읽는다. 합쳐진 호출이 몇 번이든 한 번이다.
  bool _readAgain = false;

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
    while (_readAgain) {
      _readAgain = false;
      await _load(quiet: false);
    }
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
