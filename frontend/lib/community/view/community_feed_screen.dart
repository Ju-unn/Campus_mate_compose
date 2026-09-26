import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_sheets.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 15d 커뮤니티 피드(pen `XhEyI`). 전체 학교 한 목록(사용자 결정 1), 최신순, 무한 스크롤.
class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // 바닥에 닿기 전에 부른다 — 닿은 뒤 부르면 빈칸이 잠깐 보인다.
      if (_scroll.position.extentAfter < 400) {
        ref.read(communityFeedViewModelProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _vote(String pollId, PollChoice choice) async {
    final message = await ref.read(communityFeedViewModelProvider.notifier).vote(pollId, choice);
    if (message != null && mounted) showPollToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityFeedViewModelProvider);
    return Scaffold(
      // pen `Iblb3`: 56, 왼쪽 20 · 오른쪽 8, 제목 20/700.
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('커뮤니티', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        actions: [
          IconButton(
            tooltip: '질문 올리기',
            onPressed: () => context.push(AppRoutes.communityNew),
            // pen `uhk6J` 터치 48 · `I7U2Jp` 원 32 #F7F7F7 · `zuIJJ` plus 18.
            icon: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: AppColors.surfaceSoft, shape: BoxShape.circle),
              child: const Icon(AppIcons.plus, size: 18, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: _body(state),
      bottomNavigationBar: const AppBottomNav(current: AppTab.community),
    );
  }

  Widget _body(CommunityFeedUiState state) {
    final viewModel = ref.read(communityFeedViewModelProvider.notifier);
    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    if (state.polls.isEmpty && state.errorMessage != null) {
      return _LoadError(message: state.errorMessage!, onRetry: viewModel.refresh);
    }
    if (state.polls.isEmpty) return const _EmptyFeed();
    final now = ref.read(communityNowProvider)();
    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: ListView.separated(
        controller: _scroll,
        // pen `FXyNI`: 위아래 8 · 좌우 16, 카드 사이 12.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        itemCount: state.polls.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == state.polls.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final poll = state.polls[index];
          return PollCard(
            poll: poll,
            now: now,
            isVoting: state.votingIds.contains(poll.id),
            onVote: (choice) => _vote(poll.id, choice),
            onOpen: () => context.push('${AppRoutes.communityPoll}/${poll.id}'),
            onMore: poll.isMine ? () => showPollMenu(context, ref, poll.id) : null,
          );
        },
      ),
    );
  }
}

/// 빈 상태(pen `n2tqZ` · Empty 마스터 `TVc8b`).
class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  static const _emptyAction = '질문 올리기';

  /// AppButton 라벨(18/700)이 이 기기 글자 배율로 차지하는 폭.
  static double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: AppTypography.label),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/mascot-male.png', width: 120, height: 120),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '아직 질문이 없어요',
              textAlign: TextAlign.center,
              style: AppTypography.subtitle.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '궁금한 걸 익명으로 물어보고\n캠퍼스 사람들의 생각을 들어보세요.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.xl),
            // pen 은 연분홍 채움 — button-secondary 로 바꾼다(대장 예외). 폭은 글자 + 좌우 20(`l8vOF` = Button `HE8FZ`
            // padding [0,20], 렌더 128). AppButton 은 안쪽 여백이 0 이라 IntrinsicWidth 로는 글자 폭만 남아 글자를 재서 더한다.
            SizedBox(
              width: _labelWidth(context, _emptyAction) + 2 * 20,
              child: AppButton(
                label: _emptyAction,
                variant: AppButtonVariant.secondary,
                onPressed: () => context.push(AppRoutes.communityNew),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 첫 쪽을 못 불러왔을 때. 문구는 `Failure` 종류별 문구 그대로(502/503 → "잠시 뒤 다시 시도해 주세요" 등),
/// 모양은 `school_info_screen` 의 `_SchoolNameError` 와 같다. 실패인데 "질문이 없어요" 를 보이면 거짓말이다.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.body)),
            AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
