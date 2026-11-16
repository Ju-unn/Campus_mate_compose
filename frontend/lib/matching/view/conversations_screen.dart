import 'dart:async';

import 'package:campus_mate/chat/view/chat_dialogs.dart';
import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:campus_mate/chat/view/swipe_to_leave.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/chat/viewmodel/user_channel.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_snack_bar.dart';
import 'package:campus_mate/common/widgets/app_tab_bar.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/empty_notice.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/common/widgets/section_header.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:campus_mate/matching/view/sent_request_row.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 대화 탭이 떠 있는 동안 대화 목록을 조용히 다시 읽는 간격(2026-10-13 대장 결정, 같은 날 사용자 요청으로 5초 → 3초) —
/// 사용자 채널(`user:<내 id>`, 설계안 A)이 **안 붙었을 때**(정책 적용 전 입장 거부 · 끊김).
/// 서버가 방에서 나온 뒤 30초 동안 새 메시지 푸시를 보내지 않아, 푸시만으로는 그 사이 온 답장이 목록에 안 뜬다.
/// 한 번 읽을 때 서버가 대화 N개에 PostgREST 를 3N+3 번 부르는 무거운 요청이라 방 안 읽음 확인(2초)보다 길게 둔다.
const Duration conversationsPollFast = Duration(seconds: 3);

/// 사용자 채널이 붙어 있을 때의 간격. 새 줄 · 새 방은 이벤트로 바로 오고 이것은 이벤트 유실을 메우는 안전망이다.
const Duration conversationsPollSlow = Duration(seconds: 30);

/// [대화] 탭 받은 신청 끝 → "대화 중" 머리(pen `CeqVY` `Hdpkm` · `RI9pi` `IdrTg`). 간격 토큰(16 · 24) 사이 값이다.
const double _sectionGap = 22;

/// [대화] 탭 받은 신청 머리 → 첫 줄 · 줄 사이(pen `AHZ7H` · `uxKGx`). 간격 토큰(8 · 12) 사이 값이다.
const double _receivedGap = 10;

/// 탭 줄 아래 ~ 본문 첫 줄 사이(pen 값표 "본문 위 여백 12"). 탭 줄의 누르는 칸이 보이는 줄 아래로 4 를 더 먹으므로
/// 본문은 그만큼 덜 띄운다(faq_screen 과 같은 방식) — 보이는 간격은 12 다.
const double _bodyTop = 12 - AppTabBar.extraHitHeight;

/// 대화(DESIGN.md 화면 13, pen `CeqVY`). 앱바 아래 **[대화] · [보낸 신청]** 탭(2026-11-16 사용자 「"대화" "보낸신청" 2개로 tabbar
/// 나누는게 좋을거같은데」, 나 탭과 같은 `AppTabBar`). 처음엔 [대화] 탭이다.
/// - [대화]: **받은 신청**(있을 때만 맨 위, 헤더 고정) + **대화 중**. 둘 다 없으면 빈 화면.
/// - [보낸 신청]: 보낸 신청 줄만(섹션 머리 없음). **그 탭을 처음 열 때 읽는다**(`SentRequestsViewModel.open`) — 대화만 보려는
///   사용자에게 보낸 신청 호출을 쓰지 않는다. 연 뒤에는 탭을 다시 볼 때 · 새로고침 경로가 다시 읽는다.
/// 두 탭은 [IndexedStack] 에 함께 살아 있어 탭을 오가도 스크롤 자리가 그대로다(보낸 신청 탭은 처음 열 때 만든다).
/// 목록은 Sliver 라 보이는 줄만 그린다.
///
/// 이 화면에 **들어올 때마다**(탭을 옮겨 돌아올 때 포함) 받은 신청 · 대화 목록을 **조용히** 다시 읽는다 —
/// 실패해도 이미 보이는 줄은 그대로고 오류 줄을 새로 띄우지 않는다. 앱이 백그라운드에서 돌아올 때는 앱 루트가
/// 읽는다(`core/lifecycle/resume_refresh.dart`). 새 줄 · 새 방은 앱 루트가 듣는 사용자 채널이 바로 넣는다(`user_channel.dart`) —
/// 읽는 중이면 뷰모델 가드가 겹침을 막는다.
///
/// 화면이 맨 위에 보이고 앱이 앞에 있는 동안은 **대화 목록만** 조용히 다시 읽는다 — 사용자 채널이 붙어 있으면
/// [conversationsPollSlow], 아니면 [conversationsPollFast] 마다. 받은 신청 · 보낸 신청은 폴링하지 않는다.
///
/// 10b 에서 대화 신청을 보내고 넘어오면(`SentRequestsViewModel.announceSent`) [보낸 신청] 탭을 열고 토스트를 한 번 띄운다
/// (pen `Q1322I`). 새 줄을 따로 강조하지 않는다.
///
/// shortcut: 서버 페이지 나누기 없이 목록 전체를 한 번에 받는다 — 보낸 신청 · 대화 수가 작다(신청은 주기마다 몇 장). 한 사람이
/// 수백 줄을 갖게 되면 서버에 커서를 더하고 목록 끝에서 다음 쪽을 읽는다.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

/// 탭 순서(pen 값표: 대화 · 보낸 신청).
enum _Tab { chats, sent }

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  _Tab _tab = _Tab.chats;

  /// [보낸 신청] 탭을 이 화면에서 한 번이라도 열었다 — 열기 전에는 그 목록을 만들지도 읽지도 않는다.
  bool _sentShown = false;

  Timer? _pollTimer;

  /// 앱이 백그라운드로 가면 멈추고 돌아오면 다시 건다. 돌아온 직후의 읽기는 앱 루트가 한다(`resume_refresh.dart`).
  late final AppLifecycleListener _lifecycle;
  bool _appInForeground = true;

  /// 이 화면이 맨 위 경로인가. 상세 · 채팅방이나 다이얼로그가 덮으면 false — 가려진 목록은 읽지 않는다.
  bool _onTop = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _appInForeground = state == AppLifecycleState.resumed;
        _syncPolling();
      },
    );
    // 사용자 채널이 붙거나 끊기면 간격을 바꿔 다시 건다(붙음 30초 · 아니면 3초).
    ref.listenManual<bool>(userChannelProvider, (_, _) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _syncPolling();
    });
    // 신청 직후 — announceSent 가 이미 읽기 시작했다. 탭만 옮기고 토스트를 띄운다.
    if (ref.read(sentRequestsViewModelProvider.notifier).takeJustSent()) {
      _tab = _Tab.sent;
      _sentShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSentToast(ScaffoldMessenger.of(context), context.l10n.matchingConversationsSentToast);
      });
    }
    unawaited(ref.read(acceptancesViewModelProvider.notifier).refresh(quiet: true));
    unawaited(ref.read(conversationsViewModelProvider.notifier).refresh(quiet: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 이 경로가 맨 위에서 벗어나거나 돌아올 때 다시 불린다(ModalRoute.isCurrentOf 가 변화를 구독한다).
    _onTop = ModalRoute.isCurrentOf(context) ?? true;
    _syncPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// 화면이 보이고 앱이 앞에 있을 때만 타이머를 돌린다.
  void _syncPolling() {
    if (!_appInForeground || !_onTop) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    final interval = ref.read(userChannelProvider) ? conversationsPollSlow : conversationsPollFast;
    _pollTimer ??= Timer.periodic(interval, (_) => _pollConversations());
  }

  /// 조용히 읽는다 — 실패해도 있던 줄은 그대로고 오류 줄은 없다(다음 주기에 다시). 읽는 중이면 뷰모델 가드가 합쳐 겹치지 않는다.
  void _pollConversations() {
    unawaited(ref.read(conversationsViewModelProvider.notifier).refresh(quiet: true));
  }

  /// 탭을 바꾼다 — 움직임 없이 바로(AppTabBar 규칙). [보낸 신청] 을 볼 때마다 조용히 읽는다(처음이면 그때 처음 읽는다).
  void _select(int index) {
    final tab = _Tab.values[index];
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      if (tab == _Tab.sent) _sentShown = true;
    });
    if (tab == _Tab.sent) unawaited(ref.read(sentRequestsViewModelProvider.notifier).open());
  }

  // 매칭 성사(12)로 보내는 일은 받은 신청 · 프로필 보기(`acceptance_detail_screen.dart`)가 한다 — 2026-10-16 부터
  // 결정은 그 화면에서만 보낸다(행에는 "프로필 보기" 하나뿐). 여기 두면 그 화면 위에 12 가 한 장 더 쌓인다.
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      // 유리 내비(pen `xtj0K`) 뒤로 본문이 이어진다 — 아래 여백은 본문 MediaQuery padding.bottom(알약 + 띄움 + safe area).
      extendBody: true,
      // 탭 앱바 제목은 x20 에서 시작한다(pen).
      appBar: AppBar(titleSpacing: 20, title: Text(l10n.matchingConversationsTitle, style: AppTypography.navTitle)),
      bottomNavigationBar: const GlassBottomNav(current: AppTab.chat),
      // 아래는 비우지 않는다 — 각 상태가 알약 자리를 직접 피한다(목록은 알약 뒤로 이어진다).
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 탭 이름: "대화"(앱바 제목과 같은 글) · "보낸 신청"(옛 섹션 머리와 같은 글). 수는 붙이지 않는다(pen 값표).
            AppTabBar(
              labels: [l10n.matchingConversationsTitle, l10n.matchingConversationsSentSection],
              selected: _tab.index,
              onSelected: _select,
            ),
            Expanded(
              child: IndexedStack(
                index: _tab.index,
                children: [
                  const _ChatsTab(),
                  if (_sentShown) const _SentTab() else const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 10b 신청 직후 토스트(pen `Q1322I`, Toast `I8UOWm`). 하단 내비 위 16 · 가로 가운데 — 15d 투표 토스트와 같은 자리다.
/// 기다리는 보낸 신청 줄을 누를 때도 같은 자리 · 같은 모양으로 띄운다([icon] 만 다르다).
void _showSentToast(ScaffoldMessengerState messenger, String label, {IconData icon = AppIcons.check}) {
  showToastSnackBar(
    messenger..hideCurrentSnackBar(),
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // SnackBar 기본(바깥 아래 10 + 안쪽 위아래 14)을 걷어 내야 내비 위 16 이 된다(poll_toast.dart 와 같다).
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      // 04-2 토스트와 같은 3초(pen 에 표시 시간이 없다).
      duration: const Duration(seconds: 3),
      content: Center(
        child: AppToast(
          leading: Icon(icon, size: 16, color: AppColors.onInk),
          label: label,
        ),
      ),
    ),
  );
}

/// [대화] 탭 — 받은 신청(있을 때만, 헤더 고정) + 대화 중. 13a 밀어 나가기 · 로딩 화면은 이 탭 안이다.
class _ChatsTab extends ConsumerWidget {
  const _ChatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acceptances = ref.watch(acceptancesViewModelProvider);
    final chats = ref.watch(conversationsViewModelProvider);

    if (acceptances.isLoading || chats.isLoading) {
      return const _SkeletonRows();
    }
    // 두 섹션 중 먼저 실패한 하나만 한 줄로 보인다(받은 신청 → 대화 중).
    final error = acceptances.error ?? chats.error;
    // 본문이 유리 내비 뒤까지 이어진다 — 알약 자리(본문 MediaQuery padding.bottom).
    final navInset = MediaQuery.paddingOf(context).bottom;
    if (acceptances.acceptances.isEmpty && chats.conversations.isEmpty) {
      // 빈 상태는 알약 위 영역 가운데에 둔다.
      return Padding(
        padding: EdgeInsets.only(bottom: navInset),
        child: _EmptyState(
          title: context.l10n.matchingConversationsEmptyTitle,
          description: context.l10n.matchingConversationsEmptyBody,
          error: error,
        ),
      );
    }
    return RefreshIndicator(
      // 이 탭 것만 다시 읽는다 — 보낸 신청은 그 탭에서.
      onRefresh: () => Future.wait([
        ref.read(acceptancesViewModelProvider.notifier).refresh(),
        ref.read(conversationsViewModelProvider.notifier).refresh(),
      ]),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: _bodyTop)),
          if (error != null) SliverToBoxAdapter(child: _ErrorLine(failure: error)),
          ..._acceptanceSlivers(context, acceptances),
          // 받은 신청 끝 → "대화 중" 머리 22(pen `CeqVY` `Hdpkm` · `RI9pi` `IdrTg`). 둘 다 있을 때만.
          if (acceptances.acceptances.isNotEmpty && chats.conversations.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: _sectionGap)),
          ..._conversationSlivers(context, ref, chats),
          // 끝 여백 16 + 알약 자리 — 마지막 줄이 알약 위 16 에 멈춘다.
          SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md + navInset)),
        ],
      ),
    );
  }

  /// 수락 대기. 대화 목록이 길어져도 **상단에 sticky 로 고정**한다(§8.6).
  /// 행의 "프로필 보기" 는 받은 신청 · 프로필 보기(pen `o4QqYR`)를 push 로 연다 — 결정은 거기서 한다(사용자 결정 10-16).
  List<Widget> _acceptanceSlivers(BuildContext context, AcceptancesUiState state) {
    if (state.acceptances.isEmpty) {
      return const [];
    }
    return [
      PinnedHeaderSliver(
        child: _SectionHeader(title: context.l10n.matchingConversationsReceivedSection, count: state.acceptances.length),
      ),
      // 머리 → 첫 줄 10 · 줄 사이 10(pen `AHZ7H` · `uxKGx`). 간격 토큰(8 · 12) 사이 값이다.
      const SliverToBoxAdapter(child: SizedBox(height: _receivedGap)),
      SliverList.separated(
        itemCount: state.acceptances.length,
        separatorBuilder: (context, index) => const SizedBox(height: _receivedGap),
        itemBuilder: (context, index) {
          final acceptance = state.acceptances[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: AcceptanceRow(
              acceptance: acceptance,
              onViewProfile: () => context.push('${AppRoutes.acceptanceDetail}/${acceptance.cardId}'),
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
        child: _SectionHeader(title: context.l10n.matchingConversationsChatsSection, count: state.conversations.length),
      ),
      // 머리 → 첫 줄 4(pen `pWxXI`).
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxs)),
      SliverList.separated(
        itemCount: state.conversations.length,
        separatorBuilder: (context, index) =>
            // pen [대화] 탭 줄 사이 선(`PHlzV` · `IAi6M`) #EBEBEB — [보낸 신청] 탭과 같다.
            const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
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

/// [보낸 신청] 탭(pen `ULllO` 의 줄, 섹션 머리 없음). 줄은 바탕 없이 본문 여백 16 안에 서고 사이에 hairline-soft 1px 선이 있다.
/// 순서는 서버 그대로(최신 신청 먼저).
class _SentTab extends ConsumerWidget {
  const _SentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sentRequestsViewModelProvider);
    if (state.isLoading) {
      return const _SkeletonRows();
    }
    final error = state.error;
    final navInset = MediaQuery.paddingOf(context).bottom;
    if (state.requests.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: navInset),
        child: _EmptyState(
          title: context.l10n.matchingConversationsSentEmptyTitle,
          description: context.l10n.matchingConversationsSentEmptyBody,
          error: error,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(sentRequestsViewModelProvider.notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: _bodyTop)),
          if (error != null) SliverToBoxAdapter(child: _ErrorLine(failure: error)),
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
                // 사용자 요청(11-12) — 기다리는 줄은 방이 없어 열 곳이 없다. 아이콘은 그 줄 칩과 같은 타이머(pen 값 받기 전 임시).
                onWaitingTap: () => _showSentToast(
                  ScaffoldMessenger.of(context),
                  context.l10n.matchingSentWaitingToast,
                  icon: AppIcons.timer,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md + navInset)),
        ],
      ),
    );
  }
}

/// 섹션 헤더(pen `Ymhdq`·`Yjs6e`). 우측은 "N명" — §8.6 은 "3 / 5" 같은 분수 표기를 금지한다.
/// pen 머리(`P5A282` · `Yjs6e`)는 제목 글자 칸(25)이 그대로 머리 칸이다 — 위아래 빈칸을 두지 않는다(2026-11-16 검토, 옛 최소 44).
/// 높이를 박지 않아 글자를 키우면 같이 늘어난다. 누르는 곳이 아니라 44 누름 칸 규칙은 해당하지 않는다.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      // B3: 공통 목록형 머리 — 제목 18/700 ink · 오른쪽 "N명" 14 muted(옛 20/600 에서 pen Ymhdq 값으로).
      child: SectionHeader(
        title: title,
        trailing: context.l10n.matchingConversationsSectionCount(count: count),
      ),
    );
  }
}

/// 탭마다 빈 화면 — [대화] 는 "아직 시작된 대화가 없어요", [보낸 신청] 은 "아직 보낸 신청이 없어요"(pen 값표).
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.description, this.error});

  final String title;
  final String description;
  final Failure? error;

  @override
  Widget build(BuildContext context) {
    final failure = error;
    // pen `LD7Kb` = Empty `TVc8b`: 마스코트 120 → 24 → 제목 → 8 → 설명. 실패하면 설명 아래 16 에 한 줄이 붙는다.
    return EmptyNotice(
      image: Image.asset('assets/images/mascot-female.webp'),
      title: title,
      description: description,
      action: failure == null ? null : _ErrorLine(failure: failure),
      actionGap: AppSpacing.md,
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Text(
        context.errorText(failure),
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
      ),
    );
  }
}

/// 조회 중(pen `lpsOn`). 수락 대기 스켈레톤 2행 + 채팅 스켈레톤 3행. 탭 줄 아래 12 에서 시작한다.
class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // 아래는 알약 자리를 더한다(본문이 유리 내비 뒤까지 이어진다).
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        _bodyTop,
        AppSpacing.md,
        AppSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
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
