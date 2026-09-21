import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 대화(DESIGN.md 화면 13, pen `CeqVY`). 이번 조각이 그리는 것은 상단 "수락 대기" 섹션뿐이고,
/// "대화 중" 목록은 조각 5 다 — §8.6 의 "건수가 0이면 섹션을 그리지 않는다" 규칙이 그대로 적용된다.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acceptancesViewModelProvider);
    ref.listen(acceptancesViewModelProvider, (previous, next) {
      final nickname = next.matchedNickname;
      if (nickname != null && previous?.matchedNickname != nickname) {
        ref.read(acceptancesViewModelProvider.notifier).consumeMatched();
        context.push(AppRoutes.matchMade, extra: nickname);
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text('대화', style: AppTypography.navTitle)),
      bottomNavigationBar: const AppBottomNav(current: AppTab.chat),
      body: SafeArea(child: _Body(state: state)),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final AcceptancesUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading) {
      return const _SkeletonRows();
    }
    if (state.acceptances.isEmpty) {
      return _EmptyState(errorMessage: state.errorMessage);
    }
    final viewModel = ref.read(acceptancesViewModelProvider.notifier);
    final isBusy = state.respondingCardId != null;
    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _SectionHeader(count: state.acceptances.length),
        ),
        if (state.errorMessage != null)
          SliverToBoxAdapter(child: _ErrorLine(message: state.errorMessage!)),
        SliverList.separated(
          itemCount: state.acceptances.length,
          separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (context, index) {
            final acceptance = state.acceptances[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: AcceptanceRow(
                acceptance: acceptance,
                onReject: isBusy
                    ? null
                    : () => viewModel.respond(acceptance.cardId, CardDecision.reject),
                onAccept: isBusy
                    ? null
                    : () => viewModel.respond(acceptance.cardId, CardDecision.accept),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
      ],
    );
  }
}

/// 섹션 헤더(pen `Ymhdq`). 우측은 "N명" — §8.6 은 "3 / 5" 같은 분수 표기를 금지한다.
class _SectionHeader extends SliverPersistentHeaderDelegate {
  const _SectionHeader({required this.count});

  final int count;

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Text('수락 대기', style: AppTypography.title.copyWith(color: AppColors.ink)),
          ),
          Text('$count명', style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeader oldDelegate) => oldDelegate.count != count;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('아직 시작된 대화가 없어요', style: AppTypography.title.copyWith(color: AppColors.ink)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '서로 수락하면 여기에서 대화를 시작할 수 있어요.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ErrorLine(message: errorMessage!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
      ),
    );
  }
}

/// 조회 중(pen `lpsOn`). `Skeleton · AcceptanceRow`(`R688B`) 2행을 정적으로 둔다.
class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: List<Widget>.generate(
        2,
        (_) => Container(
          height: 104,
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surfaceStrong,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}
