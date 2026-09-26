import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 17c 투표 상세(pen `BwL1G`). 카드는 피드와 같은 크기이고 질문만 다 보인다.
/// 들어오는 길이 피드 하나뿐이라 피드 목록의 같은 글을 본다 — 여기서 투표하면 피드도 같이 바뀐다.
class PollDetailScreen extends ConsumerWidget {
  const PollDetailScreen({required this.pollId, super.key});

  final String pollId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poll = ref.watch(
      communityFeedViewModelProvider.select((state) => state.polls.where((p) => p.id == pollId).firstOrNull),
    );
    final isVoting = ref.watch(communityFeedViewModelProvider.select((state) => state.votingIds.contains(pollId)));
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
        title: Text('투표 상세', style: AppTypography.navTitle),
      ),
      body: poll == null
          ? Center(child: Text('질문을 찾을 수 없어요', style: AppTypography.body.copyWith(color: AppColors.body)))
          // pen `ZR52B`: 세로 간격 16, 안쪽 16.
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                PollCard(
                  poll: poll,
                  now: ref.read(communityNowProvider)(),
                  isVoting: isVoting,
                  onVote: (choice) => _vote(context, ref, choice),
                ),
                const SizedBox(height: AppSpacing.md),
                // pen `LyR5Y` 12/500 #929292 → muted(대장 예외, 대비 4.5:1).
                Text(
                  '댓글 기능은 아직 준비 중이에요',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted),
                ),
              ],
            ),
    );
  }

  Future<void> _vote(BuildContext context, WidgetRef ref, PollChoice choice) async {
    final message = await ref.read(communityFeedViewModelProvider.notifier).vote(pollId, choice);
    if (message != null && context.mounted) showPollToast(context, message);
  }
}
