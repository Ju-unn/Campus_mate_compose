import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/feed_poll_card.dart';
import 'package:campus_mate/community/view/poll_sheets.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 질문하기 알약(pen `dDWPl`) 높이 52 와 유리 내비 위 띄움 12.
const double _askHeight = 52;
const double _askLift = AppSpacing.sm;

/// 15d 커뮤니티 피드 — 개선안 A(pen `IzG2p` > 17A `FBT9K` · 17A-2 `O8hjge`). 전체 학교 한 목록(사용자 결정 1), 최신순, 무한 스크롤.
/// 회색 바탕 위 흰 큰 카드([FeedPollCard]), 앱바 오른쪽 + 대신 유리 내비 위에 뜬 "질문하기" 알약.
/// 빠른 보기 탭(`XfcKQ` 전체 · 인기 · 내 질문 · 내 투표)은 서버 정렬 · 필터가 없어 넣지 않았다(사용자 결정).
class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});

  /// 질문하기 알약. 시험이 자리 · 접힘을 잰다.
  static const askButtonKey = Key('community-ask-button');

  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  final _scroll = ScrollController();

  /// 스크롤을 내리면 알약이 동그라미로 접히고, 올리면 펼친다(pen 메모 4).
  bool _askCollapsed = false;

  /// 지금 떠 있는 토스트 수. 토스트가 알약 자리에 뜨니(17A-2) 그동안 알약을 숨긴다.
  int _openToasts = 0;

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
    if (message != null && mounted) _track(showPollToast(context, message));
  }

  void _track(PollToast? toast) {
    if (toast == null || !mounted) return;
    setState(() => _openToasts++);
    toast.closed.whenComplete(() {
      if (mounted) setState(() => _openToasts--);
    });
  }

  /// 손으로 스크롤한 방향만 본다 — 새 글을 불러와 목록이 늘어나는 것으로는 접히지 않는다.
  bool _onUserScroll(UserScrollNotification notification) {
    final collapsed = switch (notification.direction) {
      ScrollDirection.reverse => true,
      ScrollDirection.forward => false,
      ScrollDirection.idle => _askCollapsed,
    };
    if (collapsed != _askCollapsed) setState(() => _askCollapsed = collapsed);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityFeedViewModelProvider);
    // 빈 상태는 자기 "질문 올리기" 버튼이 있어 알약을 두지 않는다. 불러오는 중 · 실패에도 질문은 올릴 수 있게 둔다.
    final showAsk = state.isLoading || state.polls.isNotEmpty || state.errorMessage != null;
    return Scaffold(
      // 유리 내비(pen `xtj0K`) 뒤로 본문이 이어진다 — 아래 여백은 본문 MediaQuery padding.bottom(알약 + 띄움 + safe area).
      extendBody: true,
      // pen `JJAzV`(AppBar · Tab `YTDwe`): 56, 왼쪽 20, 제목 20/700. 하트 칩 · 오른쪽 버튼은 꺼져 있다 —
      // 옛 + (`Iblb3` > `uhk6J`)는 "질문하기" 알약이 대신한다.
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('커뮤니티', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
      ),
      // 알약 자리는 Scaffold 가 **본문** MediaQuery 에 넣는다 — 화면 context(Scaffold 위)에서는 safe area 뿐이라 본문 안에서 읽는다.
      body: Builder(builder: (bodyContext) {
        final navInset = MediaQuery.paddingOf(bodyContext).bottom;
        return Stack(
          children: [
            Positioned.fill(child: _body(state, navInset)),
            if (showAsk)
              // pen `dDWPl`: 오른쪽 16 · 유리 내비 위 12.
              Positioned(
                right: AppSpacing.md,
                bottom: navInset + _askLift,
                child: _AskButton(
                  collapsed: _askCollapsed,
                  hidden: _openToasts > 0,
                  onPressed: () => context.push(AppRoutes.communityNew),
                ),
              ),
          ],
        );
      }),
      bottomNavigationBar: const GlassBottomNav(current: AppTab.community),
    );
  }

  /// [navInset] 은 유리 내비 알약 자리(알약 + 띄움 + safe area).
  Widget _body(CommunityFeedUiState state, double navInset) {
    final viewModel = ref.read(communityFeedViewModelProvider.notifier);
    // 본문이 유리 내비 뒤까지 이어진다 — 목록이 아닌 상태는 알약 자리를 비우고 그 위 영역 가운데에 둔다.
    Widget aboveNav(Widget child) => Padding(padding: EdgeInsets.only(bottom: navInset), child: child);
    if (state.isLoading) return aboveNav(const Center(child: CircularProgressIndicator()));
    if (state.polls.isEmpty && state.errorMessage != null) {
      return aboveNav(_LoadError(message: state.errorMessage!, onRetry: viewModel.refresh));
    }
    if (state.polls.isEmpty) return aboveNav(const _EmptyFeed());
    final now = ref.read(communityNowProvider)();
    // pen `eFFQi`: surface-soft 바탕, 위 12 · 좌우 16, 카드 사이 12.
    return ColoredBox(
      color: AppColors.surfaceSoft,
      child: NotificationListener<UserScrollNotification>(
        onNotification: _onUserScroll,
        child: RefreshIndicator(
          onRefresh: viewModel.refresh,
          child: ListView.separated(
            controller: _scroll,
            // 글이 한두 개라 화면을 못 채워도 아래로 당겨 새로 고칠 수 있게 — 기본 물리는 짧은 목록의 당김을 막는다.
            physics: const AlwaysScrollableScrollPhysics(),
            // 아래는 유리 내비 + 띄움 12 + 질문하기 52 + 12 — 끝까지 내려도 마지막 글의 "자세히 보기" 가 알약에 가리지 않는다.
            // (pen `eFFQi` 아래 98 은 유리 내비 자리뿐이라 마지막 카드가 알약 밑에 깔린다 — 보고의 pen 수정 제안.)
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              navInset + _askLift + _askHeight + AppSpacing.sm,
            ),
            itemCount: state.polls.length + (state.isLoadingMore ? 1 : 0),
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
            // 화면 context 를 쓴다 — 마지막 글을 지우면 목록이 빈 화면으로 바뀌어 항목 쪽 context 는 사라진다(삭제 뒤 토스트).
            itemBuilder: (_, index) {
              if (index == state.polls.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final poll = state.polls[index];
              return FeedPollCard(
                // 카드 상태(방금 투표했는지)가 글 id 에 붙어 있게 — 위 글이 지워져 자리가 밀려도 섞이지 않는다.
                key: ValueKey(poll.id),
                poll: poll,
                now: now,
                isVoting: state.votingIds.contains(poll.id),
                onVote: (choice) => _vote(poll.id, choice),
                onOpen: () => context.push('${AppRoutes.communityPoll}/${poll.id}'),
                onMore: poll.isMine ? () => showPollMenu(context, ref, poll.id).then(_track) : null,
                onReport: poll.isMine ? null : () => reportPoll(context, poll.id).then(_track),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 질문하기 알약(pen `dDWPl` = Button `HE8FZ` 인스턴스 덮어쓰기): 높이 52 · [0,20] · 간격 8 · primary · 모서리 끝까지 ·
/// 그림자 #1A16192E (0,6) 16 · 흰 plus 20 + "질문하기" 16/700. 스크롤을 내리면 동그라미 52(+ 만)로 접힌다.
/// AppButton 은 폭이 늘 꽉 차고 앞 아이콘 · 알약 모양이 없어(공용 위젯을 넓히지 않으려고) 여기서 FilledButton 으로 그린다.
class _AskButton extends StatelessWidget {
  const _AskButton({required this.collapsed, required this.hidden, required this.onPressed});

  final bool collapsed;

  /// 토스트가 떠 있는 동안. 보이지도 눌리지도 읽히지도 않는다.
  final bool hidden;
  final VoidCallback onPressed;

  static const String _label = '질문하기';

  /// 떠 있는 것에만 그림자를 준다(DESIGN §6). 이 버튼에만 있는 값이라 AppElevation 에 올리지 않는다.
  static const List<BoxShadow> _shadow = [BoxShadow(color: Color(0x2E1A1619), offset: Offset(0, 6), blurRadius: 16)];

  @override
  Widget build(BuildContext context) {
    final instant = MediaQuery.disableAnimationsOf(context);
    final duration = instant ? Duration.zero : AppMotion.standard;
    // 펼침: 20 + plus 20 + 8 + 글자 + 20. 접힘: 16 + 20 + 16 = 52 동그라미.
    final side = collapsed ? (_askHeight - 20) / 2 : 20.0;
    final label = collapsed
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Text(_label, style: AppTypography.button.copyWith(color: AppColors.onPrimary)),
          );
    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: duration,
          curve: AppMotion.standardCurve,
          child: DecoratedBox(
            decoration: const ShapeDecoration(shape: StadiumBorder(), shadows: _shadow),
            child: FilledButton(
              key: CommunityFeedScreen.askButtonKey,
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                foregroundColor: AppColors.onPrimary,
                minimumSize: const Size(_askHeight, _askHeight),
                padding: EdgeInsets.zero,
                shape: const StadiumBorder(),
                elevation: 0,
              ).copyWith(
                // AppButton 과 같은 눌림: 색만 바꾸고 물결은 없다.
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.pressed) ? AppColors.primaryPressed : AppColors.primary,
                ),
                overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
              ),
              child: AnimatedPadding(
                padding: EdgeInsets.symmetric(horizontal: side),
                duration: duration,
                curve: AppMotion.standardCurve,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 접히면 글자가 빠지니 아이콘이 버튼 이름을 맡는다.
                    Icon(AppIcons.plus, size: 20, color: AppColors.onPrimary, semanticLabel: collapsed ? _label : null),
                    // 동작 줄이기면 바로 바꾼다 — AnimatedSize 는 시간 0 이면 자기 레이아웃 안에서 다시 레이아웃을 걸어 멈춘다.
                    if (instant) label else AnimatedSize(duration: duration, curve: AppMotion.standardCurve, child: label),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 빈 상태(pen `n2tqZ` · Empty 마스터 `TVc8b`).
class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  static const _emptyAction = '질문 올리기';

  /// AppButton 라벨(16/700, HE8FZ 2026-10-01 개편)이 이 기기 글자 배율로 차지하는 폭.
  static double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: AppTypography.button),
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
