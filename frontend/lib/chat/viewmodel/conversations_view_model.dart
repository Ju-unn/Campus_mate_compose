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

  @override
  ConversationsUiState build() {
    Future.microtask(refresh);
    return const ConversationsUiState();
  }

  Future<void> refresh() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    final result = await ref.read(chatRepositoryProvider).fetchConversations();
    state = result.when(
      onSuccess: (conversations) =>
          state.copyWith(isLoading: false, conversations: conversations),
      onFailure: (failure) =>
          state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }
}

/// 하단 내비 "대화" 탭 뱃지(DESIGN §8.8). **수락 대기 + 안 읽은 메시지의 합** —
/// 의미는 "나를 기다리는 사람 수" 하나다. 0 이면 뱃지를 그리지 않는다.
final chatBadgeCountProvider = Provider<int>((ref) {
  return ref.watch(acceptancesViewModelProvider).acceptances.length +
      ref.watch(conversationsViewModelProvider).unreadTotal;
});
