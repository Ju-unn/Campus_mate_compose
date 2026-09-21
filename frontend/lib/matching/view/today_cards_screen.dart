import 'dart:async';

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
      appBar: AppBar(
        title: Text('오늘의 카드', style: AppTypography.navTitle),
        actions: [
          IconButton(
            // 설정(16) 진입점. 내 프로필(15)이 생기면 그리로 옮긴다(Part A 가정 3).
            icon: const Icon(AppIcons.settings),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
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
class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({required this.nextIssueAt});

  final DateTime? nextIssueAt;

  @override
  Widget build(BuildContext context) {
    return _CenteredPanel(
      children: [
        Text('오늘 카드는 확인했어요', style: AppTypography.title.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _waitingSubtitle(nextIssueAt),
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (nextIssueAt != null) _CountdownText(target: nextIssueAt!),
        const SizedBox(height: AppSpacing.lg),
        Image.asset('assets/images/mascot-male-waiting.png', width: 120),
      ],
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

/// 화면 11b — 후보 풀 자체가 비었다. 초대·커뮤니티 버튼은 갈 곳이 아직 없어 넣지 않는다(백로그).
class _NoCandidatesPanel extends StatelessWidget {
  const _NoCandidatesPanel();

  @override
  Widget build(BuildContext context) {
    return _CenteredPanel(
      children: [
        Text('지금은 소개할 사람이 없어요', style: AppTypography.title.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '지금 만날 수 있는 분들은 모두 소개해드렸어요.\n새로운 사람이 들어오면 바로 알려드릴게요.',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
        Image.asset('assets/images/mascot-female-sad.png', width: 120),
      ],
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
  const _CenteredPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
