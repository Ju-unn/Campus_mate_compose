import 'dart:async';

import 'package:campus_mate/chat/view/chat_dialogs.dart';
import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:campus_mate/chat/view/swipe_to_leave.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:campus_mate/matching/view/sent_request_row.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 대화(DESIGN.md 화면 13, pen `CeqVY`). **받은 신청**(위) + **보낸 신청**(가운데, 2026-10-13 사용자 결정 B · pen `ULllO`)
/// + **대화 중**(아래) 세 섹션이고, 섹션은 각자 provider 를 보며 서로를 모른다. §8.6 의 "건수가 0이면 섹션을 그리지 않는다".
///
/// 이 화면에 **들어올 때마다**(탭을 옮겨 돌아올 때 포함) 세 목록과 안 읽은 수를 **조용히** 다시 읽는다 —
/// 실패해도 이미 보이는 줄은 그대로고 오류 줄을 새로 띄우지 않는다. 앱이 백그라운드에서 돌아올 때는 앱 루트가
/// 읽는다(`core/lifecycle/resume_refresh.dart`). 실시간 구독은 쓰지 않는다 — 읽는 중이면 뷰모델 가드가 겹침을 막는다.
///
/// 10b 에서 대화 신청을 보내고 넘어오면(`SentRequestsViewModel.announceSent`) 토스트를 한 번 띄우고, 목록이 다 그려진 뒤
/// 보낸 신청 헤더가 받은 신청 고정 헤더 바로 아래에 오도록 한 번 내린다(pen `Q1322I`). 새 줄을 따로 강조하지 않는다.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _sentHeaderKey = GlobalKey();

  /// 신청을 보내고 넘어와 아직 보낸 신청 자리로 내리지 않았다.
  bool _revealSent = false;

  @override
  void initState() {
    super.initState();
    _revealSent = ref.read(sentRequestsViewModelProvider.notifier).takeJustSent();
    if (_revealSent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSentToast(ScaffoldMessenger.of(context));
      });
    }
    unawaited(ref.read(acceptancesViewModelProvider.notifier).refresh(quiet: true));
    unawaited(ref.read(sentRequestsViewModelProvider.notifier).refresh(quiet: true));
    unawaited(ref.read(conversationsViewModelProvider.notifier).refresh(quiet: true));
  }

  /// 로딩이 끝난 첫 그림 뒤에 한 번. 보낸 신청 헤더가 없으면(읽기 실패 등) 내리지 않고 끝낸다.
  /// 고정 헤더(받은 신청) 높이는 [Scrollable.ensureVisible] 이 빼 준다 — 그 바로 아래에 헤더가 온다.
  void _revealSentOnce() {
    if (!_revealSent) return;
    _revealSent = false;
    final header = _sentHeaderKey.currentContext;
    if (header != null) unawaited(Scrollable.ensureVisible(header));
  }

  @override
  Widget build(BuildContext context) {
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
      body: SafeArea(child: _Body(sentHeaderKey: _sentHeaderKey, onLoaded: _revealSentOnce)),
    );
  }
}

/// 10b 신청 직후 토스트(pen `Q1322I`, Toast `I8UOWm`). 하단 내비 위 16 · 가로 가운데 — 15d 투표 토스트와 같은 자리다.
void _showSentToast(ScaffoldMessengerState messenger) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // SnackBar 기본(바깥 아래 10 + 안쪽 위아래 14)을 걷어 내야 내비 위 16 이 된다(poll_toast.dart 와 같다).
      padding: EdgeInsets.zero,
      margin: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      // 04-2 토스트와 같은 3초(pen 에 표시 시간이 없다).
      duration: Duration(seconds: 3),
      content: Center(
        child: AppToast(
          leading: Icon(AppIcons.check, size: 16, color: AppColors.onInk),
          label: '신청을 보냈어요',
        ),
      ),
    ));
}

/// pen `ULllO` 섹션 사이 간격 — 받은 신청 끝 → 보낸 신청 헤더, 보낸 신청 끝 → 대화 중 헤더. 간격 토큰(16 · 24) 사이 값이다.
const double _sectionGap = 22;

class _Body extends ConsumerWidget {
  const _Body({required this.sentHeaderKey, required this.onLoaded});

  /// 보낸 신청 헤더 — 신청 직후 이 자리로 내린다.
  final GlobalKey sentHeaderKey;

  /// 세 목록이 다 읽힌 그림이 화면에 붙은 뒤 불린다.
  final VoidCallback onLoaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acceptances = ref.watch(acceptancesViewModelProvider);
    final sent = ref.watch(sentRequestsViewModelProvider);
    final chats = ref.watch(conversationsViewModelProvider);

    // 보낸 신청도 기다린다 — 그 섹션이 로딩 뒤에 끼어들어 대화 중을 밀어내지 않게.
    if (acceptances.isLoading || sent.isLoading || chats.isLoading) {
      return const _SkeletonRows();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded());
    final errorMessage = acceptances.errorMessage ?? sent.errorMessage ?? chats.errorMessage;
    if (acceptances.acceptances.isEmpty && sent.requests.isEmpty && chats.conversations.isEmpty) {
      return _EmptyState(errorMessage: errorMessage);
    }
    return RefreshIndicator(
      onRefresh: () => Future.wait([
        ref.read(acceptancesViewModelProvider.notifier).refresh(),
        ref.read(sentRequestsViewModelProvider.notifier).refresh(),
        ref.read(conversationsViewModelProvider.notifier).refresh(),
      ]),
      child: CustomScrollView(
        slivers: [
          if (errorMessage != null) SliverToBoxAdapter(child: _ErrorLine(message: errorMessage)),
          ..._acceptanceSlivers(ref, acceptances),
          ..._sentSlivers(
            context,
            sent,
            hasAbove: acceptances.acceptances.isNotEmpty,
            hasBelow: chats.conversations.isNotEmpty,
          ),
          ..._conversationSlivers(context, ref, chats),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
        ],
      ),
    );
  }

  /// 보낸 신청(pen `ULllO`). 헤더는 고정하지 않는다 — 받은 신청 헤더만 위에 붙는다.
  /// 줄은 바탕 없이 본문 여백 16 안에 서고 사이에 hairline-soft 1px 선이 있다. 순서는 서버 그대로(최신 신청 먼저).
  List<Widget> _sentSlivers(
    BuildContext context,
    SentRequestsUiState state, {
    required bool hasAbove,
    required bool hasBelow,
  }) {
    if (state.requests.isEmpty) {
      return const [];
    }
    return [
      if (hasAbove) const SliverToBoxAdapter(child: SizedBox(height: _sectionGap)),
      SliverToBoxAdapter(
        child: _SectionHeader(key: sentHeaderKey, title: '보낸 신청', count: state.requests.length),
      ),
      // 헤더 → 첫 행 4(pen `ULllO`).
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxs)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        sliver: SliverList.separated(
          itemCount: state.requests.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
          itemBuilder: (context, index) => SentRequestRow(
            key: ValueKey(state.requests[index].cardId),
            request: state.requests[index],
            // 대화 중 행과 같은 방 경로 — 나갔거나 닫힌 방은 채팅방 화면이 지금처럼 알린다.
            onOpenChat: (matchId) => context.push('${AppRoutes.chatRoom}/$matchId'),
          ),
        ),
      ),
      if (hasBelow) const SliverToBoxAdapter(child: SizedBox(height: _sectionGap)),
    ];
  }

  /// 수락 대기. 대화 목록이 길어져도 **상단에 sticky 로 고정**한다(§8.6).
  List<Widget> _acceptanceSlivers(WidgetRef ref, AcceptancesUiState state) {
    if (state.acceptances.isEmpty) {
      return const [];
    }
    final viewModel = ref.read(acceptancesViewModelProvider.notifier);
    final isBusy = state.respondingCardId != null;
    return [
      PinnedHeaderSliver(
        child: _SectionHeader(title: '받은 신청', count: state.acceptances.length),
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
  List<Widget> _conversationSlivers(BuildContext context, WidgetRef ref, ConversationsUiState state) {
    if (state.conversations.isEmpty) {
      return const [];
    }
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(title: '대화 중', count: state.conversations.length),
      ),
      SliverList.separated(
        itemCount: state.conversations.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, thickness: 1, color: AppColors.hairline),
        itemBuilder: (context, index) {
          final conversation = state.conversations[index];
          // 13a 밀어서 나가기(결정 10, pen zMfIn) — 방 안 나가기와 같은 확인 다이얼로그 · 같은 호출.
          return SwipeToLeave(
            key: ValueKey(conversation.matchId),
            onLeave: () async {
              if (await confirmLeaveChat(context)) {
                await ref.read(conversationsViewModelProvider.notifier).leave(conversation.matchId);
              }
            },
            child: ChatListRow(
              conversation: conversation,
              onTap: () => context.push('${AppRoutes.chatRoom}/${conversation.matchId}'),
            ),
          );
        },
      ),
    ];
  }
}

/// 섹션 헤더(pen `Ymhdq`·`Yjs6e`). 우측은 "N명" — §8.6 은 "3 / 5" 같은 분수 표기를 금지한다.
/// pen 높이 44 는 최소값이다 — 44 로 고정하면 글자 1.75 배부터 제목이 조용히 잘린다.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, super.key});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      constraints: const BoxConstraints(minHeight: 44),
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
              '신청을 수락하면 여기에서 대화를 시작할 수 있어요.',
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
