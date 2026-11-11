import 'dart:async';
import 'dart:math' as math;

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/section_header.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/view/comment_input_bar.dart';
import 'package:campus_mate/community/view/comment_row.dart';
import 'package:campus_mate/community/view/comment_sheets.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_sheets.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/poll_detail_ui_state.dart';
import 'package:campus_mate/community/viewmodel/poll_detail_view_model.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 마지막 댓글까지 이만큼 남으면 다음 10개를 부른다(커뮤니티 피드의 이어 읽기와 같은 400).
const double _loadMoreExtent = 400;

/// 17c 투표 상세(pen `BwL1G`) + 댓글(pen 18 `X4HnyK` · 18a `S8tPtZ`). 카드는 피드와 같은 크기이고 질문만 다 보인다.
/// **pollId 만으로 열린다** — 푸시 알림에서 피드를 거치지 않고 들어와도 `fetchPoll` 로 글을 읽는다([PollDetailViewModel]).
/// 댓글은 오래된 순 10개씩, 버튼 없이 목록 끝 가까이 내리면 다음 10개가 이어진다(사용자 결정 11-10 「인스타처럼」).
class PollDetailScreen extends ConsumerStatefulWidget {
  const PollDetailScreen({required this.pollId, super.key});

  final String pollId;

  @override
  ConsumerState<PollDetailScreen> createState() => _PollDetailScreenState();
}

class _PollDetailScreenState extends ConsumerState<PollDetailScreen> {
  final _scroll = ScrollController();

  /// 입력줄의 지금 높이를 읽는 데 쓴다 — 여러 줄을 쓰면 80 보다 커진다(최대 4줄 약 152).
  final _inputKey = GlobalKey();

  PollDetailViewModel get _viewModel => ref.read(pollDetailViewModelProvider(widget.pollId).notifier);

  /// 토스트를 띄우는 순간의 입력줄 높이. 아직 그려지지 않았으면 기본 높이(80).
  /// 잰 높이에는 입력줄의 SafeArea(아래 안전 영역)가 들어 있는데 Scaffold 가 떠 있는 토스트를 그만큼 이미 올려 주므로 뺀다(0 아래로는 안 내린다).
  double get _inputHeight {
    final measured = _inputKey.currentContext?.size?.height;
    if (measured == null) return commentInputBarHeight;
    return math.max(0, measured - MediaQuery.paddingOf(context).bottom);
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreIfNearEnd);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 겹쳐 불려도 뷰모델이 한 번만 보낸다. 실패해 오류가 떠 있는 동안은 "다시 시도" 를 눌러야 다시 간다.
  void _loadMoreIfNearEnd() {
    if (_scroll.hasClients && _scroll.position.extentAfter < _loadMoreExtent) {
      unawaited(_viewModel.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pollDetailViewModelProvider(widget.pollId));
    // 첫 쪽이 화면을 못 채우면 스크롤이 없어 끝 가까이를 알릴 수 없다 — 그릴 때마다 한 번 확인한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMoreIfNearEnd();
    });
    return Scaffold(
      // pen `bcnJx`: 17b 와 같은 규격 — 뒤로 `b0V9g8` 48(arrow-left 22), 제목 `SKAG4` x60.
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: AppSpacing.xxs,
        leading: Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
                ),
              )
            : null,
        title: Text(context.l10n.communityDetailTitle, style: AppTypography.navTitle),
      ),
      body: _body(context, state),
    );
  }

  Widget _body(BuildContext context, PollDetailUiState state) {
    final poll = state.poll;
    if (poll == null) return _noPoll(context, state);
    return Column(
      children: [
        Expanded(
          // 아래로 당기면 글 · 댓글 첫 쪽을 다시 읽는다(사용자 11-11 「당기면 갱신」, 실시간은 보류). 피드와 같은 방식.
          child: RefreshIndicator(
            onRefresh: _viewModel.refresh,
            child: ListView(
              controller: _scroll,
              // 댓글이 적어 화면을 못 채워도 당길 수 있게 — 기본 물리는 짧은 목록의 당김을 막는다.
              physics: const AlwaysScrollableScrollPhysics(),
              // pen `ZR52B` Body: 안쪽 16, 카드 · 댓글 영역 사이 16.
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                PollCard(
                  poll: poll,
                  now: ref.read(communityNowProvider)(),
                  isVoting: state.isVoting,
                  onVote: _vote,
                  onReport: poll.isMine ? null : () => reportPoll(context, poll.id, bottomInset: _inputHeight),
                ),
                const SizedBox(height: AppSpacing.md),
                // pen Comments Header `Ymhdq` "댓글 N" 18/700 ink, 렌더 높이 25. 아래 간격 8(Comments Section gap).
                SectionHeader(title: context.l10n.communityCommentCount(count: poll.commentCount)),
                const SizedBox(height: AppSpacing.xs),
                ..._comments(context, state),
              ],
            ),
          ),
        ),
        CommentInputBar(key: _inputKey, onSend: _send, isSending: state.isSending),
      ],
    );
  }

  /// 글이 아직 없을 때: 읽는 중 · 못 읽음. 서버가 "없다" 고 답한 글(404, 가림 포함)은 있는 그대로 말하고, 그 밖의 실패는 다시 시도를 둔다.
  Widget _noPoll(BuildContext context, PollDetailUiState state) {
    final failure = state.pollError;
    if (state.isLoadingPoll || failure == null) return const Center(child: CircularProgressIndicator());
    if (failure is ServerRejectedFailure || failure is NotFoundFailure) {
      return Center(child: Text(context.l10n.communityDetailNotFound, style: AppTypography.body.copyWith(color: AppColors.body)));
    }
    return _InlineError(failure: failure, onRetry: _viewModel.refresh);
  }

  List<Widget> _comments(BuildContext context, PollDetailUiState state) {
    // 새로 고침 중에는 보이던 목록을 그대로 둔다 — 당김 표시가 이미 돈다.
    if (state.isLoadingComments && state.comments.isEmpty) return [const _Spinner()];
    final failure = state.commentsError;
    if (failure != null) return [_InlineError(failure: failure, onRetry: _viewModel.refresh)];
    if (state.comments.isEmpty) return [const _EmptyComments()];
    final now = ref.read(communityNowProvider)();
    final moreFailure = state.moreError;
    return [
      for (final comment in state.comments)
        CommentRow(
          key: ValueKey('comment-${comment.id}'),
          comment: comment,
          now: now,
          onMore: hasCommentMenu(comment) ? () => _openMenu(comment) : null,
        ),
      if (state.isLoadingMoreComments) const _Spinner(),
      if (moreFailure != null) _InlineError(failure: moreFailure, onRetry: _viewModel.retryLoadMore),
    ];
  }

  Future<void> _vote(PollChoice choice) async {
    final l10n = context.l10n;
    final notice = await _viewModel.vote(choice);
    if (notice != null && mounted) showPollToast(context, pollVoteNoticeText(l10n, notice), bottomInset: _inputHeight);
  }

  /// 보냈으면 true. 실패하면 이유를 토스트로 알리고 false — 입력줄이 쓴 글을 칸에 되돌린다.
  Future<bool> _send(String body) async {
    final failure = await _viewModel.send(body);
    if (!mounted) return failure == null;
    if (failure != null) {
      _showFailureAfterRelayout(failure);
      return false;
    }
    _scrollToEndNextFrame();
    return true;
  }

  /// 보내는 동안 입력칸은 비워져 한 줄 높이로 줄어 있다 — 실패하면 쓴 글이 돌아와 다시 늘어난다. 그 프레임이 끝난 뒤
  /// 높이를 재야 4줄 입력에서도 토스트가 칸을 가리지 않는다. 그 프레임이 오도록 한 번 요청해 둔다.
  void _showFailureAfterRelayout(Failure failure) {
    final message = context.errorText(failure);
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) showPollToast(context, message, bottomInset: _inputHeight);
      })
      ..ensureVisualUpdate();
  }

  /// 방금 보낸 댓글이 입력줄 위에 보이도록 목록 끝으로 내린다. 동작 줄이기면 바로 간다.
  void _scrollToEndNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(end);
      } else {
        unawaited(_scroll.animateTo(end, duration: AppMotion.standard, curve: Curves.easeOut));
      }
    });
  }

  Future<void> _openMenu(PollComment comment) => showCommentMenu(
        context,
        comment: comment,
        toastBottomInset: _inputHeight,
        onDelete: () => _viewModel.deleteComment(comment.id),
      );
}

/// 목록 끝 · 첫 쪽 읽는 중 표시. 작게 둔다(AppButton 의 스피너와 같은 20 / 선 2).
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}

/// 댓글이 없을 때(pen `EmptyLine` vXGE6): 328×86, 안쪽 [32,16], 가운데, 14 muted 줄높이 1.55.
class _EmptyComments extends StatelessWidget {
  const _EmptyComments();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.md),
      child: Center(
        child: Text(context.l10n.communityCommentEmpty, style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
      ),
    );
  }
}

/// 읽기 실패: 이유 한 줄 + "다시 시도". 첫 쪽 · 이어 읽기 · 글 읽기가 같이 쓴다(피드의 공통 RetryNotice 와 같은 모양, 글자만 14).
class _InlineError extends StatelessWidget {
  const _InlineError({required this.failure, required this.onRetry});

  final Failure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.errorText(failure), textAlign: TextAlign.center, style: AppTypography.bodySmall.copyWith(color: AppColors.body)),
            AppButton(label: context.l10n.commonRetry, variant: AppButtonVariant.text, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
