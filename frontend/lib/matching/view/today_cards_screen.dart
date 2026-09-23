import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 오늘 탭(DESIGN.md 화면 10 `W0CjO` · 11 `i4VFS` · 11b `iQZoa`).
/// 화면이 다섯 모양으로 갈리는 판단은 전부 [TodayCardsViewModel] 이 했다.
class TodayCardsScreen extends ConsumerWidget {
  const TodayCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todayCardsViewModelProvider);
    return Scaffold(
      // 탭 앱바 제목은 x20 에서 시작한다(pen). 오른쪽 아이콘은 없다 —
      // 알림 종은 "메인" 탭에만 두기로 했고(2026-09-23 사용자 결정), 설정 진입점은 따로 정해진다.
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('오늘의 카드', style: AppTypography.navTitle),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.today),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ref.read(todayCardsViewModelProvider.notifier).refresh,
          child: switch (state.phase) {
            TodayCardsPhase.loading => const _SkeletonCards(),
            TodayCardsPhase.cards => _CardList(cards: state.cards),
            TodayCardsPhase.waiting => _WaitingPanel(nextIssueAt: state.nextIssueAt),
            TodayCardsPhase.noCandidates => const _NoCandidatesPanel(),
            TodayCardsPhase.failed => _FailedPanel(message: state.errorMessage),
          },
        ),
      ),
    );
  }
}

/// 첫 조회 중(화면 `Ukg21`). 반짝임 애니메이션은 두지 않는다 — 시안 `x4FuK` 도 정적이다.
class _SkeletonCards extends StatelessWidget {
  const _SkeletonCards();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: List<Widget>.generate(
        2,
        (_) => Container(
          height: 231,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceStrong,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
    );
  }
}

class _CardList extends ConsumerWidget {
  const _CardList({required this.cards});

  final List<DailyCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: cards.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final card = cards[index];
        return DailyCardSummary(
          card: card,
          // 10b 에서 결정하고 돌아오면 목록을 다시 읽는다 — 결정한 카드가 남아 있으면 안 된다.
          onTap: () async {
            await context.push<void>('${AppRoutes.cardDetail}/${card.cardId}');
            await ref.read(todayCardsViewModelProvider.notifier).markDecided();
          },
        );
      },
    );
  }
}

/// 화면 11 — 오늘 몫은 끝났고 다음 지급일을 기다린다.
/// 세로 간격 6 · 22 · 24 · 14 는 pen `i4VFS` 실측값이라 간격 토큰과 맞지 않는다.
class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({required this.nextIssueAt});

  final DateTime? nextIssueAt;

  @override
  Widget build(BuildContext context) {
    return _CenteredPanel(
      horizontalPadding: AppSpacing.md,
      // 가운데로 모으면 시안보다 아래로 내려간다 — 앱바 아래 28 에서 시작하고 남는 공간은 아래에 둔다.
      topPadding: 28,
      children: [
        Text(
          '오늘 카드는 확인했어요',
          style: AppTypography.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _waitingSubtitle(nextIssueAt),
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        if (nextIssueAt != null) _CountdownText(target: nextIssueAt!),
        const SizedBox(height: AppSpacing.lg),
        Image.asset('assets/images/mascot-male-waiting.png', width: 88),
        const SizedBox(height: 14),
        const _TomorrowBand(),
      ],
    );
  }
}

/// "내일 만날 사람들" 띠(pen `i4VFS`). 흐린 사진 위에 잉크 막을 덮어 **얼굴이 보이지 않는다** —
/// 눌러도 아무 일도 없는 장식이라 탭 영역을 두지 않는다.
///
/// 원본이 1122×1402 라 그대로 디코드하면 6MB 를 물고 있는다. 화면에 필요한 폭은 360 남짓이라
/// [cacheWidth] 720(2배 밀도)으로 줄여 받는다. 불투명도는 [Opacity] 레이어 대신 `Image.asset` 이
/// 직접 처리하고, 옆 카운트다운이 1초마다 다시 그릴 때 블러까지 다시 계산되지 않게
/// [RepaintBoundary] 로 끊는다.
class _TomorrowBand extends StatelessWidget {
  const _TomorrowBand();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: double.infinity,
          height: 116,
          color: AppColors.surfaceStrong,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Image.asset(
                  'assets/images/person-f4-blind-v1.png',
                  fit: BoxFit.cover,
                  cacheWidth: 720,
                  opacity: const AlwaysStoppedAnimation<double>(0.55),
                ),
              ),
              ColoredBox(color: AppColors.surfaceInk.withValues(alpha: 0.55)),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('내일 만날 사람들', style: AppTypography.subtitle.copyWith(color: AppColors.onInk)),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '탭해도 열리지 않아요',
                    style: AppTypography.caption.copyWith(color: AppColors.onInkMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _weekdayNames = <String>['월', '화', '수', '목', '금', '토', '일'];

/// 화면 11 의 부제. 내일이면 시안 `k1jPSY`, 그 뒤면 `exnx7` 문구다.
String _waitingSubtitle(DateTime? nextIssueAt) {
  if (nextIssueAt == null) {
    return '새로운 사람이 준비되면 알려드릴게요';
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final issueDay = DateTime(nextIssueAt.year, nextIssueAt.month, nextIssueAt.day);
  final time = _timeLabel(nextIssueAt);
  if (issueDay.difference(today).inDays <= 1) {
    return '내일 $time에 새로운 한 명이 도착해요';
  }
  return '${_weekdayNames[nextIssueAt.weekday - 1]}요일 $time에 새로운 사람을 찾아볼게요';
}

String _timeLabel(DateTime value) {
  final isMorning = value.hour < 12;
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '${isMorning ? '오전' : '오후'} $hour시';
}

/// 남은 시간 `hh:mm:ss`. 1초마다 갱신하고 [dispose] 에서 타이머를 반드시 끈다.
class _CountdownText extends StatefulWidget {
  const _CountdownText({required this.target});

  final DateTime target;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.target.difference(DateTime.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    String two(int value) => value.toString().padLeft(2, '0');
    return Text(
      '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}',
      style: AppTypography.countdown.copyWith(color: AppColors.ink),
    );
  }
}

/// 화면 11b(pen `iQZoa`) — 후보 풀 자체가 비었다.
/// 초대·커뮤니티 버튼은 갈 곳이 아직 없어 넣지 않는다(백로그).
class _NoCandidatesPanel extends StatelessWidget {
  const _NoCandidatesPanel();

  @override
  Widget build(BuildContext context) {
    return _CenteredPanel(
      horizontalPadding: 20,
      children: [
        const _EmptyStage(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '지금은 소개할 사람이 없어요',
          style: AppTypography.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '지금 만날 수 있는 분들은 모두 소개해드렸어요.\n새로운 사람이 들어오면 바로 알려드릴게요.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _NotifyNotice(),
      ],
    );
  }
}

/// 11b 그림 무대(pen `iQZoa`). 좌표·크기는 전부 시안 실측값이고 무대 왼쪽 위가 기준이다.
class _EmptyStage extends StatelessWidget {
  const _EmptyStage();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 200,
      child: Stack(
        children: [
          Positioned(
            left: 30,
            top: 10,
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: 34,
            top: 28,
            child: Image.asset('assets/images/mascot-female-sad.png', width: 150),
          ),
          // 기다리는 쪽이 앞에 선다 — 겹침 순서가 뒤집히면 둘 다 잘려 보인다.
          Positioned(
            left: 140,
            top: 88,
            child: Image.asset('assets/images/mascot-male-waiting.png', width: 96),
          ),
          const Positioned(left: 18, top: 40, child: _FloatingHeart(size: 18, opacity: 0.35)),
          const Positioned(left: 196, top: 22, child: _FloatingHeart(size: 22, opacity: 0.6)),
          const Positioned(left: 30, top: 168, child: _FloatingHeart(size: 14, opacity: 0.25)),
        ],
      ),
    );
  }
}

class _FloatingHeart extends StatelessWidget {
  const _FloatingHeart({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Icon(
      AppIcons.heart,
      size: size,
      color: AppColors.primary.withValues(alpha: opacity),
    );
  }
}

/// 11b 알림 안내 상자(pen `iQZoa`). 알림 설정으로 가는 길은 아직 없다 — 안내만 한다.
class _NotifyNotice extends StatelessWidget {
  const _NotifyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
            child: const Icon(AppIcons.bellRing, size: 20, color: AppColors.primaryText),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '새로운 사람이 오면 알림을 보내드려요',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '알림은 설정에서 끄고 켤 수 있어요',
                  style: AppTypography.caption.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedPanel extends ConsumerWidget {
  const _FailedPanel({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CenteredPanel(
      children: [
        Text(
          message ?? '카드를 불러오지 못했어요',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: '다시 시도',
          onPressed: ref.read(todayCardsViewModelProvider.notifier).refresh,
        ),
      ],
    );
  }
}

/// 당겨서 새로고침이 항상 먹게 스크롤을 남긴 가운데 정렬 패널.
class _CenteredPanel extends StatelessWidget {
  const _CenteredPanel({
    required this.children,
    this.horizontalPadding = AppSpacing.lg,
    this.topPadding,
  });

  final List<Widget> children;

  /// 11 은 16, 11b 는 20 이다(pen `i4VFS`·`iQZoa`). 나머지 패널은 화면 기본 여백을 쓴다.
  final double horizontalPadding;

  /// 값을 주면 가운데 정렬 대신 **위에서부터** 쌓고 그만큼 띄운다(화면 11).
  final double? topPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              mainAxisAlignment: topPadding == null
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (topPadding != null) SizedBox(height: topPadding),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
