import 'dart:async';

import 'package:campus_mate/chat/view/chat_dialogs.dart';
import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:campus_mate/chat/view/swipe_to_leave.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/chat/viewmodel/user_channel.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
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

/// 대화 탭이 떠 있는 동안 대화 목록을 조용히 다시 읽는 간격(2026-10-13 대장 결정, 같은 날 사용자 요청으로 5초 → 3초) —
/// 사용자 채널(`user:<내 id>`, 설계안 A)이 **안 붙었을 때**(정책 적용 전 입장 거부 · 끊김).
/// 서버가 방에서 나온 뒤 30초 동안 새 메시지 푸시를 보내지 않아, 푸시만으로는 그 사이 온 답장이 목록에 안 뜬다.
/// 한 번 읽을 때 서버가 대화 N개에 PostgREST 를 3N+3 번 부르는 무거운 요청이라 방 안 읽음 확인(2초)보다 길게 둔다.
const Duration conversationsPollFast = Duration(seconds: 3);

/// 사용자 채널이 붙어 있을 때의 간격. 새 줄 · 새 방은 이벤트로 바로 오고 이것은 이벤트 유실을 메우는 안전망이다.
const Duration conversationsPollSlow = Duration(seconds: 30);

/// 대화(DESIGN.md 화면 13, pen `CeqVY`). **받은 신청**(위) + **보낸 신청**(가운데, 2026-10-13 사용자 결정 B · pen `ULllO`)
/// + **대화 중**(아래) 세 섹션이고, 섹션은 각자 provider 를 보며 서로를 모른다. §8.6 의 "건수가 0이면 섹션을 그리지 않는다".
///
/// 이 화면에 **들어올 때마다**(탭을 옮겨 돌아올 때 포함) 세 목록과 안 읽은 수를 **조용히** 다시 읽는다 —
/// 실패해도 이미 보이는 줄은 그대로고 오류 줄을 새로 띄우지 않는다. 앱이 백그라운드에서 돌아올 때는 앱 루트가
/// 읽는다(`core/lifecycle/resume_refresh.dart`). 새 줄 · 새 방은 앱 루트가 듣는 사용자 채널이 바로 넣는다(`user_channel.dart`) —
/// 읽는 중이면 뷰모델 가드가 겹침을 막는다.
///
/// 화면이 맨 위에 보이고 앱이 앞에 있는 동안은 **대화 목록만** 조용히 다시 읽는다 — 사용자 채널이 붙어 있으면
/// [conversationsPollSlow], 아니면 [conversationsPollFast] 마다. 푸시도 이벤트도 없는 사이(방에서 나온 뒤 30초, 이벤트 유실)의
/// 새 메시지 · 새 방 · 안 읽은 수가 반영된다. 탭을 옮기거나 다른 화면이 덮거나 앱이 백그라운드로 가면 멈춘다.
/// 받은 신청 · 보낸 신청은 폴링하지 않는다.
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

  /// 화면이 보이고 앱이 앞에 있을 때만 타이머를 돌린다(`student_verification_screen.dart` 의 폴링과 같은 방식).
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

  /// 로딩이 끝난 첫 그림 뒤에 한 번. 보낸 신청 헤더가 없으면(읽기 실패 등) 내리지 않고 끝낸다.
  /// 고정 헤더(받은 신청) 높이는 [Scrollable.ensureVisible] 이 빼 준다 — 그 바로 아래에 헤더가 온다.
  /// 건너뛰지 않고 standard 동안 미끄러져 내려간다 — 어디로 갔는지 보이게(DESIGN §7). 동작 줄이기면 바로 그 자리다.
  void _revealSentOnce() {
    if (!_revealSent) return;
    _revealSent = false;
    final header = _sentHeaderKey.currentContext;
    if (header == null) return;
    final instant = MediaQuery.disableAnimationsOf(context);
    unawaited(Scrollable.ensureVisible(
      header,
      duration: instant ? Duration.zero : AppMotion.standard,
      curve: AppMotion.standardCurve,
    ));
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
      // 유리 내비(pen `xtj0K`) 뒤로 본문이 이어진다 — 아래 여백은 본문 MediaQuery padding.bottom(알약 + 띄움 + safe area).
      extendBody: true,
      // 탭 앱바 제목은 x20 에서 시작한다(pen).
      appBar: AppBar(titleSpacing: 20, title: Text('대화', style: AppTypography.navTitle)),
      bottomNavigationBar: const GlassBottomNav(current: AppTab.chat),
      // 아래는 비우지 않는다 — 각 상태가 알약 자리를 직접 피한다(목록은 알약 뒤로 이어진다).
      body: SafeArea(bottom: false, child: _Body(sentHeaderKey: _sentHeaderKey, onLoaded: _revealSentOnce)),
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
    // 본문이 유리 내비 뒤까지 이어진다 — 알약 자리(본문 MediaQuery padding.bottom).
    final navInset = MediaQuery.paddingOf(context).bottom;
    if (acceptances.acceptances.isEmpty && sent.requests.isEmpty && chats.conversations.isEmpty) {
      // 빈 상태는 알약 위 영역 가운데에 둔다.
      return Padding(padding: EdgeInsets.only(bottom: navInset), child: _EmptyState(errorMessage: errorMessage));
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
          // 끝 여백 16 + 알약 자리 — 마지막 줄이 알약 위 16 에 멈춘다.
          SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md + navInset)),
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
      // 아래는 알약 자리를 더한다(본문이 유리 내비 뒤까지 이어진다).
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
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
