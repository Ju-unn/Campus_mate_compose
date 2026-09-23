import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
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

/// 대화(DESIGN.md 화면 13, pen `CeqVY`). **수락 대기**(위) + **대화 중**(아래) 두 섹션이고,
/// 두 섹션은 각자 provider 를 보며 서로를 모른다. §8.6 의 "건수가 0이면 섹션을 그리지 않는다".
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(acceptancesViewModelProvider, (previous, next) {
      final nickname = next.matchedNickname;
      if (nickname != null && previous?.matchedNickname != nickname) {
        ref.read(acceptancesViewModelProvider.notifier).consumeMatched();
        // 방으로 바로 들어가려면 닉네임만으로는 모자라다 — 매칭 id 를 같이 넘긴다.
        context.push(
          AppRoutes.matchMade,
          extra: (nickname: nickname, matchId: next.matchedMatchId),
        );
      }
    });

    return Scaffold(
      // 탭 앱바 제목은 x20 에서 시작한다(pen).
      appBar: AppBar(titleSpacing: 20, title: Text('대화', style: AppTypography.navTitle)),
      bottomNavigationBar: const AppBottomNav(current: AppTab.chat),
      body: const SafeArea(child: _Body()),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acceptances = ref.watch(acceptancesViewModelProvider);
    final chats = ref.watch(conversationsViewModelProvider);

    if (acceptances.isLoading || chats.isLoading) {
      return const _SkeletonRows();
    }
    final errorMessage = acceptances.errorMessage ?? chats.errorMessage;
    if (acceptances.acceptances.isEmpty && chats.conversations.isEmpty) {
      return _EmptyState(errorMessage: errorMessage);
    }
    return RefreshIndicator(
      onRefresh: () => Future.wait([
        ref.read(acceptancesViewModelProvider.notifier).refresh(),
        ref.read(conversationsViewModelProvider.notifier).refresh(),
      ]),
      child: CustomScrollView(
        slivers: [
          if (errorMessage != null) SliverToBoxAdapter(child: _ErrorLine(message: errorMessage)),
          ..._acceptanceSlivers(ref, acceptances),
          ..._conversationSlivers(context, chats),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
        ],
      ),
    );
  }

  /// 수락 대기. 대화 목록이 길어져도 **상단에 sticky 로 고정**한다(§8.6).
  List<Widget> _acceptanceSlivers(WidgetRef ref, AcceptancesUiState state) {
    if (state.acceptances.isEmpty) {
      return const [];
    }
    final viewModel = ref.read(acceptancesViewModelProvider.notifier);
    final isBusy = state.respondingCardId != null;
    return [
      SliverPersistentHeader(
        pinned: true,
        delegate: _SectionHeader(title: '수락 대기', count: state.acceptances.length),
      ),
      SliverList.separated(
        itemCount: state.acceptances.length,
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.xs),
        itemBuilder: (context, index) {
          final acceptance = state.acceptances[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: AcceptanceRow(
              acceptance: acceptance,
              onReject:
                  isBusy ? null : () => viewModel.respond(acceptance.cardId, CardDecision.reject),
              onAccept:
                  isBusy ? null : () => viewModel.respond(acceptance.cardId, CardDecision.accept),
            ),
          );
        },
      ),
    ];
  }

  /// 대화 중. 닫힌 방과 내가 나간 방은 서버가 이미 빼고 준다 —
  /// **상대가 나간 방은 그대로 보이고**, 미리보기에 "OO님이 채팅방을 나갔어요" 가 뜬다(결정 7).
  List<Widget> _conversationSlivers(BuildContext context, ConversationsUiState state) {
    if (state.conversations.isEmpty) {
      return const [];
    }
    return [
      SliverPersistentHeader(
        delegate: _SectionHeader(title: '대화 중', count: state.conversations.length),
      ),
      SliverList.separated(
        itemCount: state.conversations.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, thickness: 1, color: AppColors.hairline),
        itemBuilder: (context, index) {
          final conversation = state.conversations[index];
          return ChatListRow(
            conversation: conversation,
            onTap: () => context.push('${AppRoutes.chatRoom}/${conversation.matchId}'),
          );
        },
      ),
    ];
  }
}

/// 섹션 헤더(pen `Ymhdq`·`Yjs6e`). 우측은 "N명" — §8.6 은 "3 / 5" 같은 분수 표기를 금지한다.
class _SectionHeader extends SliverPersistentHeaderDelegate {
  const _SectionHeader({required this.title, required this.count});

  final String title;
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
          Expanded(child: Text(title, style: AppTypography.title.copyWith(color: AppColors.ink))),
          Text('$count명', style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeader oldDelegate) =>
      oldDelegate.count != count || oldDelegate.title != title;
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
            // pen `LD7Kb` — 마스코트 120, 줄 사이는 전부 12 다.
            Image.asset('assets/images/mascot-female.png', width: 120),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '아직 시작된 대화가 없어요',
              textAlign: TextAlign.center,
              style: AppTypography.subtitle
                  .copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '서로 수락하면 여기에서 대화를 시작할 수 있어요.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 1.5),
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

/// 조회 중(pen `lpsOn`). 수락 대기 스켈레톤 2행 + 채팅 스켈레톤 3행.
class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (var i = 0; i < 2; i++) _bar(104),
        for (var i = 0; i < 3; i++) _bar(72),
      ],
    );
  }

  Widget _bar(double height) => Container(
        height: height,
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.surfaceStrong,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      );
}
