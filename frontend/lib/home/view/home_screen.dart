import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
import 'package:campus_mate/home/view/stat_tile.dart';
import 'package:campus_mate/home/view/tag.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 09b 메인(pen `bpA8x`). hero-today · mosaic-rail · stat-panel · review-strip · campus-strip 순서.
/// 요약을 못 받으면(조회 중·실패) hero-today 만 남긴다 — 카드로 가는 길은 요약과 상관없다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(homeSummaryProvider).value;
    return Scaffold(
      // pen `o57Mt` — 제목은 x20, 오른쪽 여백 8.
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('CampusMate', style: AppTypography.navTitle.copyWith(color: AppColors.primary)),
        actions: [
          // 숫자 배지는 알림함이 생길 때까지 숨긴다(사용자 결정 2026-09-26) — 안 읽은 알림 수의 출처가 아직 없다.
          const NotifyIconButton(count: 0),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.main),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 20),
        children: [
          const _HeroToday(),
          if (summary != null) ..._summarySections(summary),
        ],
      ),
    );
  }

  List<Widget> _summarySections(HomeSummary summary) {
    return [
      const SizedBox(height: AppSpacing.md),
      const _RailHeader(),
      const SizedBox(height: 10),
      MosaicRail(images: summary.presentPeopleImages),
      const SizedBox(height: AppSpacing.md),
      // 세 숫자가 모두 0 이면 숫자 칸 줄(pen `krua8`) 대신 판 하나(`Tklrw` 의 `AJVDS`)를 둔다.
      if (summary.deliveredCards == 0 && summary.signups == 0 && summary.conversationsStarted == 0)
        const _StatEmptyPanel()
      else
      // 글자를 키워 한 칸이 늘어나면 세 칸 높이를 같이 맞춘다.
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: StatTile(icon: AppIcons.send, value: _thousands(summary.deliveredCards), label: '전달된 카드'),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: StatTile(icon: AppIcons.userPlus, value: _thousands(summary.signups), label: '가입 수'),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: StatTile(
                icon: AppIcons.messageCircle,
                value: _thousands(summary.conversationsStarted),
                label: '시작된 대화',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      _ReviewStrip(rating: summary.reviewRating, count: summary.reviewCount),
      // pen 은 16 여백 둘(`sDLEb` · `o6qaj`)을 겹쳐 둔다.
      const SizedBox(height: AppSpacing.xl),
      // pen 글자 상자 높이 20(`YIoXQ` 렌더 결과, lineHeight 속성 없음) — bodySmall 토큰은 22 라 맞춘다.
      Text(
        '참여 중인 대학',
        style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 20 / 14, color: AppColors.muted),
      ),
      const SizedBox(height: AppSpacing.xs),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final campus in summary.campuses) Tag(label: campus)]),
      // 다 채웠으면 권할 것이 없어 카드를 숨긴다(사용자 결정 2026-09-26).
      if (summary.profileCompletionPercent < 100) ...[
        const SizedBox(height: AppSpacing.md),
        _ProfileNudge(percent: summary.profileCompletionPercent),
      ],
    ];
  }

  static String _thousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// hero-today(pen `U1k8ZK`). "지금 확인하기"는 오늘 탭으로 간다.
class _HeroToday extends StatelessWidget {
  const _HeroToday();

  @override
  Widget build(BuildContext context) {
    // pen 글자 상자 높이 29(`dIoz0` · `V2NIui` 렌더 결과, lineHeight 속성 없음) — title 토큰은 28 이라 맞춘다.
    final lineStyle = AppTypography.title.copyWith(
      fontWeight: FontWeight.w700,
      height: 29 / 20,
      color: AppColors.onPrimary,
    );
    // pen 높이 160 은 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Stack(
        children: [
          Icon(AppIcons.heart, size: 108, color: AppColors.onPrimary.withValues(alpha: 0.13)),
          Padding(
            // 아래 10 은 배율 1.0 에서 20 + 글자 58 + 24 + 버튼 48 + 10 = 160 이 되게 한다.
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('오늘의 카드가', style: lineStyle),
                Text('도착했어요', style: lineStyle),
                const SizedBox(height: AppSpacing.lg),
                Material(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () => context.go(AppRoutes.today),
                    // pen 150×48 은 최소 크기다 — 글자를 키우면 버튼이 늘어난다(DESIGN §11.2).
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 150, minHeight: 48),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          child: Text('지금 확인하기', style: AppTypography.label.copyWith(color: AppColors.primaryText)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// mosaic-rail 머리줄(pen `Ab3td` 328×25, 제목 `h7wmcH`). 오른쪽 "일시정지"(`gK0eT`)는 사용자 결정(2026-09-26)으로
/// pen 에서도 지웠다 — 레일은 저절로 흐르고 누르고 있으면 멈춘다([MosaicRail]).
class _RailHeader extends StatelessWidget {
  const _RailHeader();

  @override
  Widget build(BuildContext context) {
    return Text(
      '지금 함께 있는 사람들',
      style: AppTypography.subtitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
    );
  }
}

/// 세 숫자가 모두 0 일 때의 판(pen `Tklrw` 안 `AJVDS`). 폭은 숫자 칸 줄 자리 그대로, 높이는 내용만큼.
/// 배율 1.0 에서 12 + 마스코트 72 + 8 + 문구 20 + 12 = 124.
class _StatEmptyPanel extends StatelessWidget {
  const _StatEmptyPanel();

  @override
  Widget build(BuildContext context) {
    // 테두리가 안쪽 여백을 먹지 않게 Container 대신 DecoratedBox — Container 는 테두리 폭만큼 여백을 더한다.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        // 리터럴: `AJVDS` 테두리 #E9E9E9 · 모서리 12 와 같은 토큰이 없다(hairlineSoft #EBEBEB, AppRadius.sm 8 · md 14).
        border: Border.all(color: const Color(0xFFE9E9E9)), // pen AJVDS 값, 토큰표 밖
        borderRadius: BorderRadius.circular(12), // pen AJVDS 값, 토큰표 밖
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            // `U3fkT0` = 마스터 `J2kzx` "Mascot Male · Blue Scarf".
            Image.asset('assets/images/mascot-male.png', width: 72, height: 72),
            const SizedBox(height: AppSpacing.xs),
            // `zcHB6` 14/600 — lineHeight 속성 없음, 렌더 20 이라 height 20/14.
            Text(
              '첫 기록이 쌓이는 중이에요',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600, height: 20 / 14, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// review-strip(pen `L7wKi`). 리뷰 쓰는 화면이 아직 없어 "리뷰 남기기"는 누를 곳을 두지 않는다.
class _ReviewStrip extends StatelessWidget {
  const _ReviewStrip({required this.rating, required this.count});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // pen 에서 왼쪽(171)+버튼(128)이 300 폭에 1 남기고 들어간다 — 글자가 커지면 왼쪽을 줄인다.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    rating.toStringAsFixed(1),
                    style: AppTypography.subtitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  const SizedBox(width: 6),
                  for (var i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 1),
                    const Icon(AppIcons.star, size: 13, color: AppColors.primary),
                  ],
                  const SizedBox(width: 6),
                  Text(
                    '($count명 평가)',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: Text('리뷰 남기기', style: AppTypography.label.copyWith(color: AppColors.primaryText)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 프로필 완성도 카드(pen `usk5M`). 프로필 편집 화면이 아직 없어 누를 곳을 두지 않는다.
class _ProfileNudge extends StatelessWidget {
  const _ProfileNudge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    // pen 글자 상자 높이 20(`tV9Oa` · `KjqWO`)·16(`a8UzQ`) — lineHeight 속성 없음, 렌더 결과. 토큰은 21.7·15.4 라 맞춘다.
    final lineStyle =
        AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 20 / 14, color: AppColors.ink);
    // pen 높이 92 는 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/mascot-male.png', width: 64, height: 64),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 문구는 사용자 결정 2026-09-26 — pen `tV9Oa` · `KjqWO`.
                Text('프로필을 조금 더 채우면', style: lineStyle),
                const SizedBox(height: 5),
                Text('나를 더 잘 보여 줄 수 있어요', style: lineStyle),
                const SizedBox(height: 5),
                Container(
                  width: 150,
                  height: 6,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: percent.clamp(0, 100) / 100,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '프로필 완성도 $percent%',
                  style: AppTypography.caption.copyWith(fontSize: 11, height: 16 / 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(AppIcons.chevronRight, size: 20, color: AppColors.primaryText),
        ],
      ),
    );
  }
}
