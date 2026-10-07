import 'package:campus_mate/billing/view/heart_balance_chip.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/model/store_review_url.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
import 'package:campus_mate/home/view/stat_tile.dart';
import 'package:campus_mate/home/view/tag.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 09b 메인(pen `bpA8x`). hero-today · mosaic-rail · stat-panel · review-strip · campus-strip 순서.
/// 요약을 못 받으면(조회 중·실패) hero-today 만 남긴다 — 카드로 가는 길은 요약과 상관없다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with MeToastHost<HomeScreen> {
  bool _opening = false;

  /// 상점이 열려 있는 동안 "+" 를 또 눌러도(같은 프레임의 연타 포함) 상점을 한 겹만 쌓는다.
  bool _openingStore = false;

  /// 하트 칩의 "+" → 하트 상점. 상점에서 돌아오면 잔액을 다시 읽는다(상점에서 하트가 바뀔 수 있고, 칩은 내 프로필의 잔액을 그대로 보인다).
  Future<void> _openHeartStore() async {
    if (_openingStore) return;
    _openingStore = true;
    try {
      await context.push(AppRoutes.heartStore);
    } finally {
      _openingStore = false;
    }
    if (mounted) ref.invalidate(myProfileProvider);
  }

  /// 프로필 완성도 카드 → 프로필 편집 허브. 홈 요약은 autoDispose 가 아니고 프로필 저장은 내 프로필만 새로 읽게 하므로,
  /// 편집하고 돌아오면 요약을 다시 읽어 완성도(100% 면 카드가 사라진다)를 맞춘다.
  Future<void> _editProfile() async {
    await context.push(AppRoutes.myProfileManage);
    if (mounted) ref.invalidate(homeSummaryProvider);
  }

  /// "리뷰 남기기" — 스토어 주소([Env.storeReviewUrl])가 비어 있거나 http(s) 가 아니면 "곧 열려요" 만 띄운다.
  /// 채워져 있으면 기기에서 연다(DESIGN §8.9 — 스토어 리뷰 페이지로 딥링크). 열지 못하면 조용히 끝내지 않고 실패 안내를 띄운다.
  Future<void> _openStoreReview() async {
    final uri = Uri.tryParse(ref.read(storeReviewUrlProvider).trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      showTimedToast(comingSoonToast);
      return;
    }
    if (_opening) return; // 여는 호출이 끝나기 전에 다시 눌러도 스토어를 두 번 열지 않는다
    _opening = true;
    var opened = false;
    try {
      opened = await ref.read(openUrlProvider)(uri);
    } catch (_) {
      // 기기 쪽 오류 — 아래에서 안내한다.
    } finally {
      _opening = false;
    }
    if (!opened) {
      showTimedToast(
        AppToast(
          leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
          label: const UnknownFailure().toDisplayMessage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(homeSummaryProvider).value;
    final cohort = summary?.cohort;
    return Scaffold(
      // pen `o57Mt` — 제목은 x20, 오른쪽 여백 8.
      appBar: AppBar(
        titleSpacing: 20,
        // 제목은 칩 · 종이 쓰고 남는 폭을 차지한다(pen `Trailing` 옆 fill_container). 글자를 키워 모자라면 줄이지 자르지 않는다.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('CampusMate', style: AppTypography.navTitle.copyWith(color: AppColors.primary)),
        ),
        actions: [
          // 숫자 배지는 알림함이 생길 때까지 숨긴다(사용자 결정 2026-09-26) — 안 읽은 알림 수의 출처가 아직 없다.
          // pen `Trailing`(`ihX4y` 안) — 하트 칩(`sysyz` 인스턴스 "+" 켬, 높이 44) · gap 4 · 종. 칩은 잔액을 읽는 동안 · 못 읽으면 자리째 숨는다.
          // "+" 는 하트 상점(18, `/hearts/store`)으로 간다.
          HeartBalanceChip(showPlus: true, onPlus: _openHeartStore),
          const SizedBox(width: AppSpacing.xxs),
          const NotifyIconButton(count: 0),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.main),
      // 우리 학교가 아직 첫 카드를 안 열었으면 본문만 19 대기 화면으로 바꿔 끼운다(코호트 계획서 결정 1).
      body: MeToastLayer(
        toast: timedToast,
        child: cohort != null
            ? CohortWaitView(cohort: cohort)
            : ListView(
                // pen `aEtSx` padding [8,16,0,16] — 앱바 바로 아래 첫 카드가 y8 에서 시작한다. 아래 20 은 스크롤 끝 여백(pen 은 내비가 덮는다).
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 20),
                children: [
                  const _HeroToday(),
                  if (summary != null) ..._summarySections(summary),
                ],
              ),
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
            // 칸 바탕 · 그림 확대는 pen `zUQMn` · `Rp7wY` · `iwSBr` 값(토큰표 밖).
            Expanded(
              child: StatTile(
                icon: AppIcon3d.send,
                iconScale: 1.25,
                color: const Color(0xFFFFF6F8),
                value: _thousands(summary.deliveredCards),
                label: '전달된 카드',
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: StatTile(
                icon: AppIcon3d.join,
                iconScale: 1.16,
                color: const Color(0xFFF8F5FF),
                value: _thousands(summary.signups),
                label: '가입 수',
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: StatTile(
                icon: AppIcon3d.chat,
                color: const Color(0xFFF5F7FF),
                value: _thousands(summary.conversationsStarted),
                label: '시작된 대화',
              ),
            ),
          ],
        ),
      ),
      // pen 숫자 칸 ↔ 리뷰 띠 16(`gdS3k` 외 6곳, 종전 24 — 4px 넘쳐 내비를 덮어 줄였다).
      const SizedBox(height: AppSpacing.md),
      _ReviewStrip(rating: summary.reviewRating, count: summary.reviewCount, onReview: _openStoreReview),
      // pen 은 여백 16 · 8(`sDLEb` · `o6qaj`)을 겹쳐 둔다.
      const SizedBox(height: AppSpacing.lg),
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
        _ProfileNudge(
          percent: summary.profileCompletionPercent,
          onTap: _editProfile,
        ),
      ],
    ];
  }

  static String _thousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// hero-today(pen `U1k8ZK`). "지금 확인하기"는 오늘 탭으로 간다. 하트 장식 · "결정 대기" 문구는 `lvmAj` 에만 있다.
class _HeroToday extends StatelessWidget {
  const _HeroToday();

  @override
  Widget build(BuildContext context) {
    // pen 글자 상자 높이 29(`dIoz0` · `V2NIui` 렌더 결과, lineHeight 속성 없음) — title 토큰은 28 이라 맞춘다.
    final lineStyle = AppTypography.title.copyWith(
      fontWeight: FontWeight.w700,
      height: 29 / 20,
      color: AppColors.ink,
    );
    // pen 높이 160 은 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Stack(
        children: [
          // `S49nUs` 는 위로 5 삐져나가 카드 모서리에 잘린다. 글자를 키우면 글자가 그림 위로 온다.
          Positioned(
            left: 172,
            top: -5,
            width: 160,
            height: 170,
            child: Image.asset('assets/images/home-top-mascot-couple.webp', excludeFromSemantics: true),
          ),
          Padding(
            // 아래 22 는 배율 1.0 에서 20 + 글자 58 + 12 + 버튼 48 + 22 = 160 이 되게 한다.
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('오늘의 카드가', style: lineStyle),
                Text('도착했어요', style: lineStyle),
                const SizedBox(height: AppSpacing.sm),
                Material(
                  color: AppColors.primary,
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
                          child: Text('지금 확인하기', style: AppTypography.label.copyWith(color: AppColors.onPrimary)),
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

/// review-strip(pen `L7wKi`). "리뷰 남기기" 는 스토어 리뷰 페이지로 간다 — 주소가 없는 동안은 "곧 열려요"(홈 화면이 정한다).
class _ReviewStrip extends StatelessWidget {
  const _ReviewStrip({required this.rating, required this.count, required this.onReview});

  final double rating;
  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EC), // pen L7wKi 값, 토큰표 밖
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 글자가 커지면 왼쪽을 줄인다 — 버튼 글자는 그대로 둔다.
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
                    const Icon3d(AppIcon3d.star, size: 15),
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
          // 누름 칸은 pen 버튼 칸(높이 48) 그대로다 — 모양은 바꾸지 않았다.
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onReview,
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Center(
                    child: Text('리뷰 남기기', style: AppTypography.button.copyWith(color: AppColors.primaryText)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 프로필 완성도 카드(pen `usk5M`). 카드 전체가 누름 칸이고 프로필 편집 허브(15-5)로 간다.
class _ProfileNudge extends StatelessWidget {
  const _ProfileNudge({required this.percent, required this.onTap});

  final int percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // pen 글자 상자 높이 20(`tV9Oa` · `KjqWO`)·16(`a8UzQ`) — lineHeight 속성 없음, 렌더 결과. 토큰은 21.7·15.4 라 맞춘다.
    final lineStyle =
        AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 20 / 14, color: AppColors.ink);
    // pen 높이 92 는 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
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
                        boxShadow: AppElevation.trait,
                      ),
                      // 테두리는 채움 위에 그린다 — decoration 테두리는 Container 가 안쪽 여백으로 더해 채움이 4 로 준다.
                      foregroundDecoration: BoxDecoration(
                        border: Border.all(color: const Color(0x40D8C8D9)), // pen v8D23 값, 토큰표 밖
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
        ),
      ),
    );
  }
}
