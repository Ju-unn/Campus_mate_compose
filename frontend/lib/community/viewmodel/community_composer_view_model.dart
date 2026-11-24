import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/viewmodel/community_composer_ui_state.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:campus_mate/community/viewmodel/community_composer_ui_state.dart';

/// 글쓰기 화면 하나당 하나. 화면을 닫으면 버려진다.
final communityComposerViewModelProvider =
    NotifierProvider.autoDispose<CommunityComposerViewModel, CommunityComposerUiState>(CommunityComposerViewModel.new);

/// 17b 글쓰기 — 투표 · 게시물 고르기 · 카테고리(필수) · 본문. 투표는 `POST /community/polls`(카테고리를 싣는다),
/// 게시물은 `POST /community/posts`. 하루 10개(둘 합산)를 넘으면 서버 429 문구를 그대로 보인다.
class CommunityComposerViewModel extends Notifier<CommunityComposerUiState> {
  @override
  CommunityComposerUiState build() => const CommunityComposerUiState();

  void selectKind(CommunityKind kind) => _edit(state.copyWith(kind: kind));

  void selectCategory(CommunityCategory category) => _edit(state.copyWith(category: category));

  void updateText(String text) => _edit(state.copyWith(text: text));

  /// 투표 O/X 탭(true) · 직접 적기 탭(false).
  void useDefaultOptions(bool value) => _edit(state.copyWith(usesDefaultOptions: value));

  void updateOptionA(String text) => _edit(state.copyWith(optionA: text));

  void updateOptionB(String text) => _edit(state.copyWith(optionB: text));

  /// 고치면 지난 오류는 지운다.
  void _edit(CommunityComposerUiState next) => state = next.copyWith(error: null);

  /// 올리기. 올라갔으면 true(화면이 닫는다), 못 올렸거나 보낼 수 없는 상태 · 보내는 중이면 false.
  /// 성공 뒤에는 [CommunityComposerUiState.isSubmitting] 을 켠 채 둔다 — 화면이 닫히기 전 한 번 더 눌러도 가지 않게.
  Future<bool> submit() async {
    final category = state.category;
    if (!state.canSubmit || category == null) return false;
    state = state.copyWith(isSubmitting: true, error: null);
    final result = await _send(category);
    // 보내는 사이 화면이 닫혔으면 상태는 없다 — 올라갔는지만 그대로 알린다.
    if (!ref.mounted) return result is Success;
    return result.when(
      onSuccess: (_) {
        _afterPosted();
        return true;
      },
      onFailure: (failure) {
        state = state.copyWith(isSubmitting: false, error: failure);
        return false;
      },
    );
  }

  Future<Result<void>> _send(CommunityCategory category) {
    final repository = ref.read(communityRepositoryProvider);
    final text = state.text.trim();
    if (state.kind == CommunityKind.post) return repository.createPost(category: category, body: text);
    final (optionA, optionB) = state.pollOptions();
    return repository.createPoll(category: category, question: text, optionA: optionA, optionB: optionB);
  }

  void _afterPosted() {
    // 사용 통계 `poll_create` — 투표만(게시물 이벤트는 ANALYTICS_EVENTS 표에 없다). 글 · 보기 글자는 싣지 않는다.
    if (state.kind == CommunityKind.poll) ref.read(analyticsServiceProvider).logPollCreate();
    // 어느 탭에서 왔든 전체 탭으로 옮겨 새로 받는다 — 방금 올린 글이 맨 위에 보인다(사용자 결정).
    unawaited(ref.read(communityFeedViewModelProvider.notifier).showAllAfterPosting());
  }
}
