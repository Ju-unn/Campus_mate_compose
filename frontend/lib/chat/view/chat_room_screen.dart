import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/bubble_report_menu.dart';
import 'package:campus_mate/chat/view/chat_dialogs.dart';
import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/chat/view/chat_room_menu_sheet.dart';
import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/chat/view/date_divider.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/chat/view/system_message.dart';
import 'package:campus_mate/chat/view/trust_banner.dart';
import 'package:campus_mate/chat/view/trust_gate_sheet.dart';
import 'package:campus_mate/chat/view/trust_reveal_bubble.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_view_model.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 채팅방(DESIGN.md 화면 14, pen `ioKLk`). 게이트 배너·시트(14b·14f·14g·14h)도 이 화면이 얹는다.
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final ScrollController _scroll = ScrollController();
  late final ChatRepository _repository;
  late final ConversationsViewModel _conversations;
  late final AppLifecycleListener _lifecycle;
  bool _sheetShown = false;

  /// 24시간 경계에 한 번 울린다(백로그 22). 시트는 상태가 바뀔 때만, 배너는 그릴 때만 시각을
  /// 보니 방에 머무는 동안 경계를 넘으면 아무것도 바뀌지 않았다.
  Timer? _reminderTimer;

  /// 차단 요청이 실패했을 때 입력 바 위에 띄우는 한 줄. 이 한 줄뿐이라 뷰모델을 따로 두지 않는다.
  String? _safetyError;

  @override
  void initState() {
    super.initState();
    // 화면을 닫는 순간에는 ref 를 쓸 수 없어 미리 잡아 둔다.
    _repository = ref.read(chatRepositoryProvider);
    _conversations = ref.read(conversationsViewModelProvider.notifier);
    _scroll.addListener(_loadMoreAtTop);
    // 백그라운드에 있는 동안 온 메시지는 구독으로 오지 않는다 — 돌아오면 다시 읽는다(백로그 18).
    _lifecycle = AppLifecycleListener(onResume: _reconnect);
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _lifecycle.dispose();
    _scroll.dispose();
    // 나갈 때 한 번 더 읽음을 찍는다(ERD §4) — 방에서 본 것이 목록에 안 읽은 채로 남지 않게.
    unawaited(_repository.markRead(widget.matchId).then((_) => _conversations.refresh()));
    super.dispose();
  }

  /// 리스트가 `reverse: true` 라 **끝에 닿는 것이 곧 맨 위**다.
  void _loadMoreAtTop() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      unawaited(ref.read(chatRoomViewModelProvider(widget.matchId).notifier).loadMore());
    }
  }

  DateTime _now() => ref.read(chatRoomNowProvider)();

  ChatRoomViewModel get _viewModel =>
      ref.read(chatRoomViewModelProvider(widget.matchId).notifier);

  void _reconnect() {
    if (mounted) {
      unawaited(_viewModel.reconnect());
    }
  }

  /// 방을 닫는 유일한 길(뒤로가기 · 나가기 뒤). 푸시·매칭 성사에서는 `go` 로 들어와
  /// **스택이 한 장뿐**이라 pop 할 것이 없다 — 그대로 pop 하면 디버그에서 assert 로 걸리고
  /// 릴리스에서는 빈 화면이 남는다. 그때는 대화 목록으로 내려보낸다.
  void _exit() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go(AppRoutes.conversations);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomViewModelProvider(widget.matchId));

    ref.listen(chatRoomViewModelProvider(widget.matchId), (previous, next) {
      if (next.hasLeft && previous?.hasLeft != true && context.mounted) {
        _exit();
        return;
      }
      if (next.room != null && !identical(next.room, previous?.room)) {
        _scheduleReminder(next.room!);
      }
      _maybeShowSheet(next);
    });

    final room = state.room;
    return PopScope(
      // 안드로이드 시스템 뒤로가기도 앱바 화살표와 같은 길로 보낸다(백로그 23).
      // 푸시로 연 방은 스택이 한 장이라 그냥 두면 go_router 가 pop 하지 못하고 앱이 닫힌다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _exit();
        }
      },
      child: _buildRoom(context, state, room),
    );
  }

  Widget _buildRoom(BuildContext context, ChatRoomUiState state, ChatRoom? room) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: AppColors.ink, onPressed: _exit),
        titleSpacing: 0,
        title: room == null ? null : _Title(room: room, revealed: state.room!.gate.passed),
        actions: [
          // pen `QEazm` 48×48 안 ellipsis 22. 누르면 드롭다운이 아니라 바텀시트다(pen `Lgdxu`).
          IconButton(
            icon: const Icon(AppIcons.ellipsis, size: 22, color: AppColors.ink),
            tooltip: '더보기',
            // 방을 못 읽어도 늘 누를 수 있다 — 나가기는 방을 못 읽어도 되어야 한다(main 동작 유지).
            onPressed: () => _openMenu(room?.partner),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.isDisconnected)
              TrustBanner(
                isMuted: true,
                icon: AppIcons.circleAlert,
                title: '연결이 끊겼어요',
                caption: '새 메시지가 오지 않을 수 있어요. 다시 시도하면 못 받은 메시지도 같이 가져와요',
                actionLabel: '다시 시도',
                onAction: _reconnect,
              )
            else
              _Banner(state: state, now: _now(), onAccept: _accept),
            Expanded(
              child: _MessageList(
                state: state,
                controller: _scroll,
                onBubbleLongPress: _openBubbleMenu,
                onViewProfile: room == null
                    ? () {}
                    : () => context.push('${AppRoutes.partnerProfile}/${room.partner.profileId}'),
              ),
            ),
            if ((_safetyError ?? state.errorMessage) != null)
              _ErrorLine(message: (_safetyError ?? state.errorMessage)!),
            if (state.isPartnerGone)
              const _PartnerGoneNotice()
            else
              ChatInputBar(isSending: state.isSending, onSend: _viewModel.send),
          ],
        ),
      ),
    );
  }

  /// 방을 새로 읽을 때마다 경계 Timer 를 다시 맞춘다. 이미 지난 경계면 걸지 않는다 —
  /// 그때는 [_maybeShowSheet] 가 바로 판단한다.
  void _scheduleReminder(ChatRoom room) {
    _reminderTimer?.cancel();
    final wait = room.createdAt.add(trustGateReminderAfter).difference(_now());
    if (wait <= Duration.zero) {
      return;
    }
    _reminderTimer = Timer(wait, () {
      if (!mounted) {
        return;
      }
      setState(() {});
      _maybeShowSheet(ref.read(chatRoomViewModelProvider(widget.matchId)));
    });
  }

  /// 24시간이 지났고 아직 수락하지 않았으면 **방에 들어올 때마다** 시트가 뜬다(설계 §2.5).
  void _maybeShowSheet(ChatRoomUiState state) {
    if (_sheetShown || state.stageAt(_now()) != TrustGateStage.sheet) {
      return;
    }
    _sheetShown = true;
    final deadlineAt = state.room!.gate.deadlineAt;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        // 기본 딤(0.8)은 시안보다 어둡다 — 모달 딤 토큰(0.5)을 쓴다.
        barrierColor: AppColors.scrim,
        // 16e-1 에서 바꾸고 돌아오면 방을 다시 읽는다 — 시트는 떠 있는 채로 새 아이디를 보여 준다.
        builder: (sheetContext) => Consumer(
          builder: (_, sheetRef, _) => TrustGateSheet(
            deadlineAt: deadlineAt,
            myKakaoId: sheetRef.watch(chatRoomViewModelProvider(widget.matchId).select((s) => s.room?.myKakaoId)),
            onChangeKakaoId: _changeKakaoId,
            onAccept: () {
              Navigator.of(sheetContext).pop();
              // 시트는 확인 다이얼로그를 거치지 않는다 — 공유할 아이디까지 보여 준 시트가
              // 이미 확인 절차다(pen `p0XJA6` 에 다이얼로그가 없다). 14g 배너는 그대로 한 번 더 묻는다.
              unawaited(_viewModel.acceptTrust());
            },
            onLeave: () {
              Navigator.of(sheetContext).pop();
              unawaited(_leave());
            },
          ),
        ),
      );
      // 스와이프로 닫든 버튼으로 닫든 14h 배너로 바뀐다.
      _viewModel.dismissSheet();
    });
  }

  /// 14f "변경" → 16e-1. 시트 위에 올리고, 저장하고 돌아왔을 때만(true) 방을 다시 읽는다.
  /// 방 머리말만 따로 읽는 공개 길이 없어 앱 복귀 때와 같은 [ChatRoomViewModel.reconnect] 를 쓴다.
  Future<void> _changeKakaoId() async {
    final saved = await context.push<bool>(AppRoutes.kakaoIdSettings);
    if (saved == true && mounted) {
      await _viewModel.reconnect();
    }
  }

  Future<void> _accept() async {
    if (!await confirmTrustAccept(context)) {
      return;
    }
    await _viewModel.acceptTrust();
  }

  /// 앱바 메뉴의 "나가기" 와 시트의 "거절하고 나가기" 가 **같은 다이얼로그·같은 호출**을 쓴다(결정 11).
  Future<void> _leave() async {
    if (!await confirmLeaveChat(context)) {
      return;
    }
    await _viewModel.leave();
  }

  /// ⋯ 바텀시트(pen `Lgdxu`). 지난 차단 실패 문구는 다음 동작을 고르면 지운다.
  /// [partner] 가 null 이면(방을 못 읽었다) 시트에 신고 · 차단 줄이 없어 나가기와 취소만 돌아온다.
  Future<void> _openMenu(ChatPartner? partner) async {
    setState(() => _safetyError = null);
    final action = await showChatRoomMenuSheet(context, canTargetPartner: partner != null);
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case ChatRoomMenuAction.report:
        await reportThenLeave(context, ref, ReportTarget.profile(partner!.profileId));
      case ChatRoomMenuAction.block:
        await _block(partner!);
      case ChatRoomMenuAction.leave:
        await _leave();
    }
  }

  /// 상대 말풍선 롱프레스(pen `I8fOcN`) → 팝업 "이 메시지 신고" → 신고 시트.
  Future<void> _openBubbleMenu(BuildContext bubbleContext, Message message) async {
    if (!await showBubbleReportMenu(bubbleContext, message) || !mounted) {
      return;
    }
    await reportThenLeave(context, ref, ReportTarget.message(message.id));
  }

  /// 14e 확인 → 차단 → 대화 목록(14c 와 같은 흐름). 실패하면 방에 남아 입력 바 위 한 줄로 알린다.
  Future<void> _block(ChatPartner partner) async {
    final error = await blockThenLeave(
      context,
      ref,
      profileId: partner.profileId,
      nickname: partner.nickname,
    );
    if (error != null && mounted) {
      setState(() => _safetyError = error);
    }
  }
}

/// 앱바 가운데(pen `I1aI3M`). 통과하면 아바타가 실사진으로 바뀐다 — 그 순간만 `{motion.emphasis}`.
class _Title extends StatelessWidget {
  const _Title({required this.room, required this.revealed});

  final ChatRoom room;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final photo = room.photoUrls.isEmpty ? null : room.photoUrls.first;
    final url = revealed ? (photo ?? room.partner.avatarUrl) : room.partner.avatarUrl;
    return Row(
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.emphasis,
          switchInCurve: AppMotion.emphasisCurve,
          child: _Avatar(key: ValueKey(url), url: url),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            room.partner.nickname,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.navTitle.copyWith(color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, super.key});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceStrong),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(AppIcons.userRound, size: 16, color: AppColors.disabled)
          : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
    );
  }
}

/// 헤더 아래 배너. 어느 것이 뜨는지는 [ChatRoomUiState.stageAt] 한 곳에서 정한다.
class _Banner extends StatelessWidget {
  const _Banner({required this.state, required this.now, required this.onAccept});

  final ChatRoomUiState state;

  /// 화면이 그리는 순간의 시각. 경계를 넘을 때 화면이 다시 그려 이 값이 바뀐다(백로그 22).
  final DateTime now;
  final Future<void> Function() onAccept;

  @override
  Widget build(BuildContext context) {
    final room = state.room;
    if (room == null) {
      return const SizedBox.shrink();
    }
    switch (state.stageAt(now)) {
      case TrustGateStage.preAccept:
        return TrustBanner(
          title: '카카오톡 아이디를 먼저 공유해도 돼요',
          caption: '24시간 뒤에 물어보지만, 지금 수락할 수도 있어요',
          actionLabel: '수락하기',
          onAction: () => unawaited(onAccept()),
        );
      case TrustGateStage.waiting:
        return CountdownBuilder(
          deadlineAt: room.gate.deadlineAt,
          builder: (context, remaining) => TrustBanner(
            title: '수락했어요. 상대의 응답을 기다리고 있어요',
            caption: '응답 기한까지 ${countdownLabel(remaining)} · '
                '둘 다 수락하면 카카오톡 아이디와 실제 사진이 공개돼요',
          ),
        );
      case TrustGateStage.ending:
        return CountdownBuilder(
          deadlineAt: room.gate.deadlineAt,
          builder: (context, remaining) => TrustBanner(
            isMuted: true,
            title: '이 대화는 ${coarseRemainingLabel(remaining)} 뒤 종료돼요',
            caption: '응답 기한이 지나면 대화 목록에서 사라져요',
          ),
        );
      // 시트가 뜨는 중이거나(sheet), 통과했거나(revealed), 상대가 나갔거나(none) —
      // 셋 다 헤더 아래에 배너를 얹지 않는다.
      case TrustGateStage.sheet:
      case TrustGateStage.revealed:
      case TrustGateStage.none:
        return const SizedBox.shrink();
    }
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.state,
    required this.controller,
    required this.onBubbleLongPress,
    required this.onViewProfile,
  });

  final ChatRoomUiState state;
  final ScrollController controller;

  /// 상대 텍스트 말풍선을 길게 눌렀을 때. 말풍선 자리를 잴 수 있게 그 말풍선의 context 를 넘긴다.
  final void Function(BuildContext bubbleContext, Message message) onBubbleLongPress;

  /// 14b 카드의 "상대 프로필 보기".
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final room = state.room;
    if (room == null) {
      return const SizedBox.shrink();
    }
    final items = _items(room);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            '먼저 인사를 건네 보세요',
            style: AppTypography.body.copyWith(color: AppColors.muted),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      // 아래가 최신이다. 새 줄이 와도 스크롤을 붙잡고 있을 필요가 없다.
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) => items[index],
    );
  }

  /// 오래된 것부터 쌓고 마지막에 뒤집는다 — `reverse: true` 리스트는 0번이 맨 아래다.
  List<Widget> _items(ChatRoom room) {
    final widgets = <Widget>[];
    // 14b 카드는 메시지가 아니라 `matches.trust_passed_at` 에서 나온다 — 줄로 저장하지 않는다.
    // 상대가 나갔거나 나를 차단한 방(앱에는 둘 다 "나간 방")에는 통째로 그리지 않는다 — 서버가 아이디 · 실사진을
    // 내리지 않아 "아직 등록하지 않았어요" 로 잘못 읽히고, 14c 도 404 다(사용자 결정 09-27).
    final reveal = room.gate.passed && !state.isPartnerGone
        ? TrustRevealBubble(kakaoId: room.kakaoId, onViewProfile: onViewProfile)
        : null;
    final revealAt = state.revealAnchorAt;
    var revealPlaced = reveal == null;
    DateTime? lastDay;
    for (final message in state.messages) {
      // 그 시각보다 늦은 첫 줄 **앞**에 끼운다. 날짜가 바뀌는 줄이면 구분선도 카드 뒤로 간다 —
      // 카드는 통과한 날에 속한다.
      if (!revealPlaced && revealAt != null && message.createdAt.isAfter(revealAt)) {
        widgets.add(reveal!);
        revealPlaced = true;
      }
      final day = DateUtils.dateOnly(message.createdAt);
      if (lastDay == null || day != lastDay) {
        widgets.add(DateDivider(date: message.createdAt));
        lastDay = day;
      }
      widgets.add(_bubble(room, message));
    }
    // 통과 뒤 대화가 없거나 통과 시각을 모르면(passed_at 을 내리기 전 서버) 끝에 붙는다.
    if (!revealPlaced) {
      widgets.add(reveal!);
    }
    if (state.isLoadingMore) {
      widgets.insert(0, const Center(child: CircularProgressIndicator()));
    }
    return widgets.reversed.toList();
  }

  Widget _bubble(ChatRoom room, Message message) {
    if (message.isSystem) {
      return SystemMessage(body: message.body);
    }
    // 내 id 를 따로 들고 다니지 않는다 — 상대가 아니면 내 것이다.
    if (message.senderId != room.partner.profileId) {
      return MessageBubble(message: message, isMine: true);
    }
    // 신고 메뉴는 상대 말풍선에만 있다(pen `I8fOcN`). Builder 로 이 말풍선 행의 context 를 잡는다.
    return Builder(
      builder: (bubbleContext) => MessageBubble(
        message: message,
        isMine: false,
        onLongPress: () => onBubbleLongPress(bubbleContext, message),
      ),
    );
  }
}

/// 상대가 나간 방의 입력 바 자리(결정 7, pen 없음 — Notice 스타일 한 줄).
/// **비활성 입력칸을 남겨 두지 않는다.** 눌러도 아무 일 없는 칸이 제일 나쁘다.
class _PartnerGoneNotice extends StatelessWidget {
  const _PartnerGoneNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surfaceSoft,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SafeArea(
        top: false,
        child: Text(
          '상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
      ),
    );
  }
}
