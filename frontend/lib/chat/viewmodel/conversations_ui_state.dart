import 'package:campus_mate/chat/model/conversation.dart';

/// 대화 중 목록(화면 13 아래 섹션)의 상태. 수락 대기 섹션과는 서로를 모른다.
class ConversationsUiState {
  const ConversationsUiState({
    this.isLoading = true,
    this.conversations = const [],
    this.errorMessage,
  });

  final bool isLoading;
  final List<Conversation> conversations;
  final String? errorMessage;

  /// 하단 내비 뱃지의 절반(DESIGN §8.8 — 나머지 절반은 수락 대기 건수다).
  int get unreadTotal =>
      conversations.fold(0, (sum, conversation) => sum + conversation.unreadCount);

  ConversationsUiState copyWith({
    bool? isLoading,
    List<Conversation>? conversations,
    String? errorMessage,
  }) {
    return ConversationsUiState(
      isLoading: isLoading ?? this.isLoading,
      conversations: conversations ?? this.conversations,
      errorMessage: errorMessage,
    );
  }
}
