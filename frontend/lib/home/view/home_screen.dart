import 'dart:async';

import 'package:campus_mate/billing/store/view/heart_balance_chip.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/pressable.dart';
import 'package:campus_mate/common/widgets/retry_notice.dart';
import 'package:campus_mate/consent/model/repository/open_url.dart';
import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/core/app_update/update_requirement_provider.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/data/home_people.dart';
import 'package:campus_mate/home/model/data/home_summary.dart';
import 'package:campus_mate/home/model/data/instagram_link.dart';
import 'package:campus_mate/home/model/data/profile_completion_item.dart';
import 'package:campus_mate/home/view/auto_marquee.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/home_banner_carousel.dart';
import 'package:campus_mate/home/view/home_grid.dart';
import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
import 'package:campus_mate/home/view/tag.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/home/viewmodel/hero_today.dart';
import 'package:campus_mate/home/viewmodel/home_people_provider.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/matching/view/countdown_text.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/tour_target.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 리뷰 띠(pen `L7wKi`) — 시험이 크기 · 자리를 재는 표식.
const Key homeReviewStripKey = ValueKey('home-review-strip');

/// 프로필 완성도 카드(칩 판) · 그 게이지 — 시험이 크기 · 자리를 재는 표식.
const Key homeProfileNudgeKey = ValueKey('home-profile-nudge');
const Key homeProfileGaugeKey = ValueKey('home-profile-gauge');

/// 09b 메인(pen `bpA8x` → `M5hpo7` 10-15 → 홈 v3 `kkKiZ` 11-12 → 시안 A `TdmIQ` 11-16). hero-today → 24 → mosaic-rail → 24 →
/// 배너 슬라이드(있을 때만) → 24 → 링크 칸(인스타그램 · 문의하기) → 24 → 리뷰 띠(스토어가 있는 기기만) → 24 → campus-strip → 24 →
/// 완성도 카드(칩 판). 요약을 받는 중이면 hero-today 만, 못 받으면 그 아래 공용 실패 안내(다시 시도 · 앱 복귀 때 다시 읽기)만 남긴다 —
/// 카드로 가는 길은 요약과 상관없다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with MeToastHost<HomeScreen> {
  bool _opening = false;

  /// 알림함이 열려 있는 동안 종을 또 눌러도 한 겹만 쌓는다.
  bool _openingInbox = false;

  /// 요약 블록 도착 효과는 이 화면에서 요약을 **처음 받을 때만** 보인다 — 이미 받아 둔 요약으로 다시 들어오거나
  /// 다시 읽을 때(프로필 편집에서 돌아옴)는 움직이지 않는다. 한 번 요약을 그리면 false 로 닫힌다.
  late bool _summaryArriving = ref.read(homeSummaryProvider).value == null;

  /// 앱 투어 자동 시작을 이 화면에서 한 번만 묻는다(본 적이 있는지는 뷰모델이 계정별로 본다).
  bool _tourAsked = false;

  /// 학교가 열린 홈(요약을 받았고 코호트 대기가 아님)에 왔을 때만 — 오픈 전 계정은 오픈 뒤 첫 홈에서 본다.
  void _askTourOnce() {
    if (_tourAsked) return;
    _tourAsked = true;
    // 그리는 도중에 provider 를 바꾸지 않게 다음 차례로 미룬다.
    Future.microtask(() {
      if (mounted) unawaited(ref.read(appTourViewModelProvider.notifier).autoStart());
    });
  }

  /// 요약을 못 받은 채 앱이 다시 앞으로 오면 다시 읽는다(사용자 결정 2026-11-16 「다시 시도 + 자동」).
  /// 홈 화면이 살아 있는 동안(위에 알림함 · 상점 등을 띄운 때 포함) 이 화면이 맡는다 — 실패일 때만 읽어 해가 없다.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 종 배지의 안 읽은 수 — 홈에 들어올 때 읽는다(앱이 돌아올 때는 resume_refresh, 알림함에서 돌아올 때는 아래 [_openNotifications]).
    unawaited(ref.read(unreadCountProvider.notifier).refresh());
    _lifecycle = AppLifecycleListener(onResume: _rereadIfMissing);
    // 못 받은 채 다른 탭에 갔다 돌아오면 옛 실패 안내가 남지 않게 한 번 다시 읽는다. 처음 받는 중이면 그대로 기다린다.
    // 그리는 도중에 provider 를 바꾸지 않게 다음 차례로 미룬다.
    Future.microtask(() {
      if (mounted) _rereadIfMissing();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// 요약이 비어 있을 때(못 받음)만 다시 읽는다 — 받아 둔 요약은 그대로 두어 돈 드는 호출을 늘리지 않는다. 읽는 중이면 겹쳐 부르지 않는다.
  void _rereadIfMissing() {
    final state = ref.read(homeSummaryProvider);
    if (_summaryFailed(state) && !state.isLoading) ref.invalidate(homeSummaryProvider);
  }

  /// 요약을 한 번 읽어 봤는데 없다(저장소가 실패를 null 로 준다) — 처음 받는 중과 가른다. 다시 읽는 동안에도 앞 결과(null)를 들고 있어 그대로 true 다.
  static bool _summaryFailed(AsyncValue<HomeSummary?> state) =>
      state.value == null && (state.hasValue || state.hasError);

  /// 종 → 알림함(09c). 돌아오면 안 읽은 수를 다시 읽는다 — 알림함에서 읽은 것이 배지에 맞게 줄어 있어야 한다.
  Future<void> _openNotifications() async {
    if (_openingInbox) return;
    _openingInbox = true;
    try {
      await context.push(AppRoutes.notifications);
    } finally {
      _openingInbox = false;
    }
    if (mounted) unawaited(ref.read(unreadCountProvider.notifier).refresh());
  }

  /// 상점이 열려 있는 동안 "+" 를 또 눌러도(같은 프레임의 연타 포함) 상점을 한 겹만 쌓는다.
  bool _openingStore = false;

  /// 하트 칩의 "+" → 하트 상점. 상점에서 돌아오면 잔액을 다시 읽는다(상점에서 하트가 바뀔 수 있고, 칩은 내 프로필의 잔액을 그대로 보인다).
  Future<void> _openHeartStore() async {
    if (_openingStore) return;
    _openingStore = true;
    try {
      await context.push(AppRoutes.heartStore, extra: HeartStoreEntry.home);
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

  /// 기기 앱 · 브라우저로 연다(링크 칸 인스타그램 · 리뷰 띠 스토어). 열지 못하면 조용히 끝내지 않고 실패 안내를 띄운다.
  Future<void> _openExternal(Uri uri) async {
    if (_opening) return; // 여는 호출이 끝나기 전에 다시 눌러도 두 번 열지 않는다
    _opening = true;
    var opened = false;
    try {
      opened = await ref.read(openExternalUrlProvider)(uri);
    } catch (_) {
      // 기기 쪽 오류 — 아래에서 안내한다.
    } finally {
      _opening = false;
    }
    if (!opened && mounted) {
      showTimedToast(
        AppToast(
          leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
          label: context.errorText(const UnknownFailure()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryState = ref.watch(homeSummaryProvider);
    final summary = summaryState.value;
    final cohort = summary?.cohort;
    if (summary != null && cohort == null) _askTourOnce();
    final animateSummary = _summaryArriving;
    if (summary != null) _summaryArriving = false;
    // 레일 사람 칸 — 요약과 따로 받는다. 09b 를 그릴 때(요약이 왔고 학교가 열렸을 때)만 부른다 — 학교 대기(코호트) 사용자와
    // 요약을 못 받아 학교가 열렸는지 모를 때는 부르지 않는다. 받는 중 · 못 받음 · 인원 부족이면 기본 그림 칸이다.
    final people = summary != null && cohort == null
        ? ref.watch(homePeopleProvider).value ?? HomePeople.none
        : HomePeople.none;
    // 내 학교 — 앱바 하트 칩이 이미 읽는 내 프로필에서 꺼낸다(서버 요약에는 없다). 못 읽으면 강조 없이 둔다.
    final mySchool = ref.watch(
      myProfileProvider.select((profile) => profile.value?.when(onSuccess: (me) => me.university, onFailure: (_) => null)),
    );
    return Scaffold(
      // 유리 내비(pen `xtj0K`) 뒤로 본문이 이어진다 — 아래 여백은 본문 MediaQuery padding.bottom(알약 + 띄움 + safe area).
      extendBody: true,
      // pen `o57Mt` — 제목은 x20, 오른쪽 여백 8.
      appBar: AppBar(
        titleSpacing: 20,
        // 제목은 칩 · 종이 쓰고 남는 폭을 차지한다(pen `Trailing` 옆 fill_container). 글자를 키워 모자라면 줄이지 자르지 않는다.
        // 학교 오픈 전에는 제목이 없다(pen `D4Q6U/PjvNd` 끔, 사용자 「campusmate 로고 없고」 11-11) — 톱니는 actions 라 오른쪽 그대로.
        title: cohort != null
            ? null
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('CampusMate', style: AppTypography.navTitle.copyWith(color: AppColors.primary)),
              ),
        actions: [
          // 학교 오픈 전(pen `tUaGw` 앱바 `D4Q6U`) — 하트 칩 · 종을 끄고 오른쪽 48 칸에 톱니(settings 22 #6A6A6A)만 둔다.
          // 그때는 홈과 설정만 열리고(출시 전 막기, 사용자 결정 11-11) 설정이 로그아웃 · 탈퇴 · 문의로 가는 문이다.
          if (cohort != null)
            IconButton(
              tooltip: context.l10n.meProfileSettingsTooltip,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(AppIcons.settings, size: 22, color: AppColors.muted),
              onPressed: () => context.push(AppRoutes.settings),
            )
          else ...[
            // 숫자 배지: 2026-09-26 에 알림함이 없어 숨겼다가(`count: 0` 고정) 알림함(09c)이 생겨 다시 켠다 — 0 이면 없고, 99 를 넘으면 "99+".
            // pen `Trailing`(`ihX4y` 안) — 하트 칩(`sysyz` 인스턴스 "+" 켬, 높이 44) · gap 4 · 종. 칩은 잔액을 읽는 동안 · 못 읽으면 자리째 숨는다.
            // "+" 는 하트 상점(18, `/hearts/store`)으로 간다.
            HeartBalanceChip(showPlus: true, onPlus: _openHeartStore),
            const SizedBox(width: AppSpacing.xxs),
            NotifyIconButton(count: ref.watch(unreadCountProvider), onTap: _openNotifications),
          ],
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      // 학교 오픈 전에는 하단 내비가 없다(pen `tUaGw`) — 탭이 가리키는 곳이 모두 막혀 있다.
      bottomNavigationBar: cohort != null ? null : const GlassBottomNav(current: AppTab.main),
      // 우리 학교가 아직 첫 카드를 안 열었으면 본문만 19 대기 화면으로 바꿔 끼운다(코호트 계획서 결정 1).
      body: MeToastLayer(
        toast: timedToast,
        child: cohort != null
            ? CohortWaitView(cohort: cohort)
            // 알약 자리는 Scaffold 가 **본문** MediaQuery 에 넣는다 — 이 화면 context(Scaffold 위)에서는 safe area 뿐이라 본문 안 context 로 읽는다.
            : Builder(
                builder: (bodyContext) => ListView(
                  // pen `aEtSx` padding [8,16,0,16] — 앱바 바로 아래 첫 카드가 y8 에서 시작한다. 아래 20 은 스크롤 끝 여백,
                  // 그 밑에 알약 자리(pen `eA1oQ` 하단 여백 98 = 알약 66 + 띄움 12 + safe area 20)를 더한다.
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    20 + MediaQuery.paddingOf(bodyContext).bottom,
                  ),
                  children: [
                    const TourTarget(id: TourTargetId.homeHero, child: _HeroToday()),
                    if (summary != null)
                      ..._summarySections(summary, people: people, animate: animateSummary, mySchool: mySchool)
                    else if (_summaryFailed(summaryState)) ...[
                      // 요약 자리 — 블록 사이와 같은 24 아래에 앱 공용 작은 실패 안내(pen 에 홈 실패 상태가 없다).
                      // 저장소가 실패 종류를 null 로 삼켜 나 탭 · 계정 불러오기 실패와 같은 일반 안내다. 다시 읽는 동안에도 자리를 지키고 버튼만 돈다(깜빡임 없음).
                      const SizedBox(height: AppSpacing.lg),
                      RetryNotice.inline(
                        message: context.appErrorText(AppError.tryLater),
                        busy: summaryState.isLoading,
                        onRetry: () => ref.invalidate(homeSummaryProvider),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  /// 요약 블록(레일 · 배너 슬라이드 · 링크 칸 · 리뷰 띠 · 참여 대학 · 완성도 카드, 시안 A 11-16). 블록 사이는 모두 24. 숨는 블록(배너 0장,
  /// 스토어 없는 기기의 리뷰 띠, 완성도 100)은 위 여백째 빠진다. 숫자 3칸은 사용자 결정(11-12)으로 뺐다 — 서버 칸은 옛 앱이 읽어 그대로 있다.
  /// [animate] 면 블록마다 투명 · 아래 8 에서 40ms 간격으로 올라온다(DESIGN §7 standard, 처음 받을 때만).
  List<Widget> _summarySections(
    HomeSummary summary, {
    required HomePeople people,
    required bool animate,
    required String? mySchool,
  }) {
    // 리뷰 띠가 여는 기기 스토어(아이폰은 리뷰 쓰기 창). 스토어가 없는 웹 · 데스크톱은 null — 띠를 그리지 않는다.
    final storeUrl = ref.watch(storeListingProvider).reviewUrl();
    final blocks = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailHeader(examples: people.isEmpty),
          const SizedBox(height: 10),
          MosaicRail(people: people),
        ],
      ),
      // 사용자 결정(11-12): 사람 줄 아래 · 링크 칸 위. 0장이면 앞 여백째 빠진다.
      if (summary.banners.isNotEmpty) HomeBannerCarousel(banners: summary.banners),
      // 이벤트 칸이 빠져 9b-1 이벤트 화면(`/events`)으로 가는 길은 없다 — 화면 · 경로는 그대로 둔다(사용자 결정 11-12 「두기」).
      // 문의하기 칸은 에브리타임 칸 자리다(사용자 「메인에 … "에브리타임" -> 삭제」 · 시안 「A로 하고」 11-16) — 앱 안 문의 화면.
      HomeGrid(
        onInstagram: () => _openExternal(instagramLink),
        onInquiry: () => unawaited(context.push(AppRoutes.inquiry)),
      ),
      // 사용자 「링크 있으니깐 리뷰 살리기 가능하지 않나?」(11-15) — 평가 0명이어도 숨기지 않는다. 숫자는 서버 값 그대로, 보상은 없다.
      if (storeUrl != null)
        _ReviewStrip(
          rating: summary.reviewRating,
          count: summary.reviewCount,
          onReview: () => _openExternal(Uri.parse(storeUrl)),
        ),
      _CampusStrip(campuses: summary.campuses, mySchool: mySchool),
      // 다 채웠으면 권할 것이 없어 카드를 숨긴다(사용자 결정 2026-09-26). 10-15 에 잠깐 뺐다가 사용자 요청으로 되살렸다(pen `xEpOD`).
      if (summary.profileCompletionPercent < 100)
        TourTarget(
          id: TourTargetId.homeProfileNudge,
          child: _ProfileNudge(
            percent: summary.profileCompletionPercent,
            missing: summary.profileCompletionMissing,
            onTap: _editProfile,
          ),
        ),
    ];
    return [
      for (final (index, block) in blocks.indexed) ...[
        const SizedBox(height: AppSpacing.lg),
        Entrance(rise: 8, delay: _blockStagger * index, enabled: animate, child: block),
      ],
    ];
  }

  /// 요약 블록 도착 간격(대장 지시 — 모션 기회 4, pen 에 없는 값)
  static const Duration _blockStagger = Duration(milliseconds: 40);

}

/// hero-today 세 상태 + 불러오는 중(DESIGN §8.9 · pen `VdvmY`). 모양은 [heroTodayProvider] 가 오늘 탭 상태로 고른다.
/// 상태가 바뀌면 `{motion.standard}` 로 겹쳐 바꾼다 — 기기 "동작 줄이기"면 바로 바꾼다.
class _HeroToday extends ConsumerWidget {
  const _HeroToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.standard,
      switchInCurve: AppMotion.standardCurve,
      switchOutCurve: AppMotion.standardCurve,
      child: switch (ref.watch(heroTodayProvider)) {
        // pen `jHiXf` — surface-soft 틀 · 마스코트 그대로, 문구 · 버튼 자리에 `dX7EM`(x20 y20 세로 쌓기) 막대 셋.
        // 반짝임 없이 정적이다(DESIGN §7, pen context "애니메이션 없음").
        HeroLoading() => Semantics(
            key: const ValueKey('loading'),
            label: context.l10n.homeHeroLoading,
            child: const _HeroFrame(
              color: AppColors.surfaceSoft,
              children: [
                _SkeletonBar(width: 148, height: 20), // `BJJfw`
                SizedBox(height: AppSpacing.xs), // `GL4q4` 8
                _SkeletonBar(width: 112, height: 20), // `YHQnE`
                SizedBox(height: 22), // `izWX7` 22 — 간격 토큰(16 · 24) 사이 값
                _SkeletonBar(width: 104, height: 32), // `nBNDt`
              ],
            ),
          ),
        HeroArrived() => _HeroFrame(
            key: const ValueKey('arrived'),
            color: AppColors.primaryWash,
            children: [
              ..._HeroFrame.lines(context.l10n.homeHeroArrivedLine1, context.l10n.homeHeroArrivedLine2),
              const SizedBox(height: AppSpacing.sm),
              _HeroButton(context.l10n.homeHeroArrivedButton),
            ],
          ),
        HeroPending(:final count) => _HeroFrame(
            key: const ValueKey('pending'),
            color: AppColors.primaryWash,
            badge: _PendingBadge(count),
            children: [
              ..._HeroFrame.lines(context.l10n.homeHeroPendingLine1, context.l10n.homeHeroPendingLine2(count: count)),
              const SizedBox(height: AppSpacing.sm),
              _HeroButton(context.l10n.homeHeroPendingButton),
            ],
          ),
        HeroDone(:final nextIssueAt) => _HeroFrame(
            key: const ValueKey('done'),
            color: AppColors.surfaceSoft,
            // pen `xq5wi` — 위아래 16, 높이 128 안에서 가운데. 버튼이 없다(이미 확인했다).
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: AppSpacing.md),
            centered: true,
            children: [
              ..._HeroFrame.lines(context.l10n.homeHeroDoneLine1, context.l10n.homeHeroDoneLine2),
              if (nextIssueAt != null) ...[
                const SizedBox(height: AppSpacing.xs),
                // `GC85E` 14/400 lh 1.5 muted · `FMjgB` 32/700 자간 -0.96 — 렌더 44(lineHeight 속성 없음).
                Text(context.l10n.homeHeroNextCard, style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted)),
                // 글자를 키워 숫자가 칸보다 넓어지면 자르지 않고 줄인다(한 덩어리라 줄을 바꿀 곳이 없다).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: CountdownText(
                    target: nextIssueAt,
                    // display(32/700 · 자간 -0.96)에 숫자 폭 고정(tabular)만 더한다 — 1초마다 바뀌어도 폭이 흔들리지 않게.
                    style: AppTypography.display.copyWith(
                      height: 44 / 32,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                      color: AppColors.ink,
                    ),
                    // 0 이 되면 푸시를 기다리지 않고 다시 읽는다 — 00:00:00 에 멈춰 있지 않게(재시도 상한은 뷰모델).
                    onDone: () => unawaited(ref.read(todayCardsViewModelProvider.notifier).refreshWhenDue()),
                  ),
                ),
              ],
            ],
          ),
      },
    );
  }
}

/// hero 한 장의 틀(pen `U1k8ZK` · `fxlhV` · `HGxAR` · 불러오는 중 `jHiXf`). 모든 상태가 같은 틀이다 — 모서리 32, 최소 높이 160(DESIGN §8.9 · 미결 46,
/// 글자를 키우면 늘어난다 §11.2). 커플 마스코트(`S49nUs`)는 오른쪽 끝에서 -4 · 위 -5 · 160×170 — 왼쪽 x172 고정이면 320 폭에서
/// 잘리고 430 폭에서 빈 곳이 생긴다(pen context). 위로 5 삐져나가 모서리에 잘리고, 글자를 키우면 글자가 그림 위로 온다.
class _HeroFrame extends StatelessWidget {
  const _HeroFrame({
    required this.color,
    required this.children,
    this.padding = const EdgeInsets.all(20),
    this.centered = false,
    this.badge,
    super.key,
  });

  final Color color;
  final List<Widget> children;
  final EdgeInsets padding;
  final bool centered;
  final Widget? badge;

  /// 두 줄 제목 20/700 #222. pen 글자 상자 27(`dIoz0` · `P0SAU` · `fvepr` 렌더, lineHeight 속성 없음) — title 토큰은 28 이라 맞춘다.
  static List<Widget> lines(String first, String second) {
    final style = AppTypography.title.copyWith(fontWeight: FontWeight.w700, height: 27 / 20, color: AppColors.ink);
    return [Text(first, style: style), Text(second, style: style)];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // AnimatedSwitcher 가 느슨한 폭을 줘도 줄 폭을 다 쓴다.
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 160),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Stack(
        // 최소 높이를 글 칸까지 넘겨야 확인 완료가 가운데에 선다.
        fit: StackFit.passthrough,
        children: [
          Positioned(
            right: -4,
            top: -5,
            width: 160,
            height: 170,
            child: Image.asset('assets/images/home-top-mascot-couple.webp', excludeFromSemantics: true),
          ),
          Padding(
            padding: padding,
            child: Column(
              mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
          if (badge case final badge?) Positioned(top: AppSpacing.md, right: AppSpacing.md, child: badge),
        ],
      ),
    );
  }
}

/// hero 버튼(pen `t0Un8s` · `yfRCy` 150×48 r14 #FF385C, 글자 18/700 흰색). 오늘 탭으로 간다 — 카드로 가는 유일한 유도 지점(§8.9).
class _HeroButton extends StatelessWidget {
  const _HeroButton(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
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
              child: Text(label, style: AppTypography.label.copyWith(color: AppColors.onPrimary)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 결정 대기 장수 배지(pen `Q4nCLG` — hero 우상단 16 · 32×24 · #FF385C 알약, 숫자 10/600 흰색). 0 이면 hero 가 결정 대기 상태가 아니라 안 뜬다.
/// 같은 수를 hero 문구가 이미 말하므로 스크린리더에는 읽히지 않는다.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text('$count', style: AppTypography.badge.copyWith(color: AppColors.onPrimary)),
      ),
    );
  }
}

/// hero 불러오는 중의 막대 하나(pen `TmUDw` Skeleton · Block — #EBEBEB · 모서리 6). 글자가 아니라 글자를 키워도 크기가 그대로다.
/// 알림함 스켈레톤(`notifications_screen.dart` `_SkeletonRow._bar`)과 같은 값이지만 그쪽이 private 라 여기 따로 둔다.
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.hairlineSoft, borderRadius: BorderRadius.circular(6)), // pen TmUDw 모서리 6, 토큰 밖
      ),
    );
  }
}

/// campus-strip(pen `YIoXQ` 제목 + `zOaUW` 칩 줄). 내 학교 칩을 맨 앞에 두고 강조한다(pen `T2Pfi4`).
class _CampusStrip extends StatelessWidget {
  const _CampusStrip({required this.campuses, required this.mySchool});

  final List<String> campuses;
  final String? mySchool;

  /// 칩 사이(pen `zOaUW` gap 6).
  static const double _chipGap = 6;

  /// 이 수부터 칩 줄이 사람 레일처럼 흐른다(사용자 지시 10-15). 그보다 적으면 줄바꿈 칩 줄 그대로 멈춰 있다.
  static const int _flowFrom = 5;

  @override
  Widget build(BuildContext context) {
    final mine = campuses.contains(mySchool) ? mySchool : null;
    final tags = [
      if (mine != null) Tag(label: mine, mine: true),
      for (final campus in campuses)
        if (campus != mine) Tag(label: campus),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 섹션 제목 18/700 ink(대장 10-15 — 종전 14/700 muted). 줄높이는 레일 제목과 같다.
        Text(context.l10n.homeSectionColleges, style: _sectionTitleStyle),
        const SizedBox(height: AppSpacing.xs),
        if (tags.length < _flowFrom) Wrap(spacing: _chipGap, runSpacing: _chipGap, children: tags),
        if (tags.length >= _flowFrom)
          // 한 줄(높이 28)로 이어 붙여 사람 레일과 같은 규칙(오른쪽 · 20px/초 · 누르면 멈춤 · 동작 줄이기면 손으로)으로 흐른다.
          AutoMarquee(
            cycle: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tag in tags) ...[tag, const SizedBox(width: _chipGap)],
              ],
            ),
          ),
      ],
    );
  }
}

/// 홈 섹션 제목(지금 함께 있는 사람들 · 참여 중인 대학) 18/700 ink, 글자 상자 25(pen `M5hpo7` 좌표표 10-15 — subNavTitle 토큰은 27).
final TextStyle _sectionTitleStyle = AppTypography.subNavTitle.copyWith(height: 25 / 18, color: AppColors.ink);

/// mosaic-rail 머리줄(pen `Ab3td` 328 폭, 제목 `h7wmcH`). 오른쪽 "일시정지"(`gK0eT`)는 사용자 결정(2026-09-26)으로
/// pen 에서도 지웠다 — 레일은 저절로 흐르고 누르고 있으면 멈춘다([MosaicRail]).
/// 레일이 기본 상태(서버 빈 목록 · 받는 중 · 못 받음, 토끼 칸만 흐른다)면 제목을 바꾼다 — 지금 보여 줄 사람이 없는데
/// "함께 있는 사람들" 이라 하지 않게(10-16 추천안, 11-13 예시 그림 제거). 실제 사람 칸이 나오면 원래 제목이다.
class _RailHeader extends StatelessWidget {
  const _RailHeader({required this.examples});

  final bool examples;

  @override
  Widget build(BuildContext context) {
    return Text(examples ? context.l10n.homeRailTitleExamples : context.l10n.homeRailTitle, style: _sectionTitleStyle);
  }
}

/// review-strip(pen 마스터 `L7wKi`, 시안 A `TdmIQ` — 링크 칸 아래). 높이 64 · `reviewStripSurface` · 모서리 14 · 좌우 14.
/// 평가가 있으면 별점 18/700(pen `O2fN3`, subtitle) + 3D 별 15 다섯 + "(N명 평가)" 12/500 muted(평가 수를 모르면 — 안드로이드 — 이 글자만 뺀다),
/// 없으면(0명 · 못 읽음) 그 자리에 "CampusMate 가 마음에 드셨나요?"
/// 14/600 ink 한 줄(pen `QCtib`). 오른쪽 "리뷰 남기기" 16/700 primaryText(누름 높이 48)는 기기 스토어 상세를 연다.
class _ReviewStrip extends StatelessWidget {
  const _ReviewStrip({required this.rating, required this.count, required this.onReview});

  final double rating;

  /// null = 스토어가 평가 수를 주지 않는다(안드로이드 플레이 보고서) — 별점만 보인다.
  final int? count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final rated = rating > 0 && count != 0;
    return Container(
      key: homeReviewStripKey,
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.reviewStripSurface,
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
              child: rated ? _rating(context) : _prompt(context),
            ),
          ),
          // 누름 칸은 pen 버튼 칸(높이 48) 그대로다. 평가 0명이면 글 211 + 버튼 77 이 328 에 들어가게 가로 여백이 없다(pen `QCtib`).
          Pressable(
            onTap: onReview,
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: rated ? AppSpacing.md : 0),
                child: Center(
                  child: Text(context.l10n.homeReviewButton, style: AppTypography.button.copyWith(color: AppColors.primaryText)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rating(BuildContext context) => Row(
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
          if (count case final known?) ...[
            const SizedBox(width: 6),
            Text(
              context.l10n.homeReviewCount(count: known),
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted),
            ),
          ],
        ],
      );

  Widget _prompt(BuildContext context) => Text(
        context.l10n.homeReviewPrompt,
        maxLines: 1,
        style: AppTypography.labelSmall.copyWith(height: 1.4, color: AppColors.ink),
      );
}

/// 프로필 완성도 카드(pen `usk5M` → `xEpOD` / `e26o6` Profile Completion Banner 10-15 — 328×92 · primary-wash · 모서리 24 · 오른쪽 chevron,
/// 마스코트 없음). 카드 전체가 누름 칸이고 프로필 편집 허브(15-5)로 간다. main 80e7b8b0 의 구현을 그대로 되살렸다.
class _ProfileNudge extends StatelessWidget {
  const _ProfileNudge({required this.percent, required this.missing, required this.onTap});

  final int percent;

  /// 안 채운 항목(서버 순서). 비면(옛 서버 · 다 채움) 칩 줄과 그 위 간격을 그리지 않는다.
  final List<ProfileCompletionItem> missing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = l10n.homeProfileNudgeCompletion(percent: percent);
    final chips = [for (final item in missing) _chipText(l10n, item)];
    // 화면 읽기는 카드 하나로 읽는다 — 칩은 따로 눌리지 않는 표시라 따로 읽지 않는다.
    final spoken = chips.isEmpty ? title : l10n.homeProfileNudgeMissingSemantics(percent: percent, items: chips.join(', '));
    // 높이는 내용이 정한다(칩 한 줄 94 · 두 줄 128) — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Semantics(
      container: true,
      button: true,
      label: spoken,
      onTap: onTap,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          key: homeProfileNudgeKey,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primaryWash,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(AppIcons.chevronRight, size: 20, color: AppColors.primaryText),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _Gauge(percent: percent),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final text in chips) _NudgeChip(text: text)],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 칩 글자(사용자 「칩은 "사진 더 채우기"」 11-16).
  static String _chipText(AppLocalizations l10n, ProfileCompletionItem item) => switch (item) {
        ProfileCompletionItem.photos => l10n.homeProfileNudgePhotos,
        ProfileCompletionItem.mbti => l10n.homeProfileNudgeMbti,
        ProfileCompletionItem.preferredHeight => l10n.homeProfileNudgePreferredHeight,
        ProfileCompletionItem.interestTags => l10n.homeProfileNudgeInterestTags,
      };
}

/// 완성도 게이지 — 높이 6 · 카드 안쪽 폭 전체. 색 · 모서리 · 테두리는 종전 게이지 그대로.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: homeProfileGaugeKey,
      height: 6,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppElevation.trait,
      ),
      // 테두리는 채움 위에 그린다 — decoration 테두리는 Container 가 안쪽 여백으로 더해 채움이 4 로 준다.
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: AppColors.profileNudgeTrackEdge, width: 0.5), // pen `Iy7RO`
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
    );
  }
}

/// 안 채운 항목 칩 — 높이 28 · 알약 · 좌우 10 · 흰 바탕 · 12/400 primaryText(pen `mV0TB`). 누르지 않는 표시(카드 전체가 누름 칸).
class _NudgeChip extends StatelessWidget {
  const _NudgeChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadius.pill)),
      // 글자 크기만큼만 차지하고(Wrap 안에서 줄 폭으로 늘지 않게) 높이 28 안 세로 가운데 — 글자를 키우면 칩이 늘어난다.
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(text, style: AppTypography.caption.copyWith(color: AppColors.primaryText)),
      ),
    );
  }
}
