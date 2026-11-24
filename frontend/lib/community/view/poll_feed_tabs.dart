import 'dart:async';

import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/view/community_category_look.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/tour_target.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 15d 탭 줄(pen 17 `J0vMj5` > StoryStrip `qZ5qm`): 폭 꽉 · 안쪽 [4,16,12,16] · 탭 7개(`XfcKQ` 72×86) 사이 4 ·
/// 바탕 투명(뒤 canvas 흰) · 아래 구분선 없음. 앱바 `bottom` 에 꽂아 목록과 같이 스크롤되지 않는다 — 높이는 [heightFor].
/// 합 528 이 화면보다 넓어 가로로 민다 — 360 폭에서 5번째 탭이 반쯤 보이는 것이 pen 의도다.
/// 밀 수 있다는 안내(19-3, pen 25-F1 `MUBW9` · `RXFHp`): 커뮤니티에 들어올 때마다 [hintDelay] 뒤 한 번
/// 끝까지 갔다가 돌아온다(왕복 [hintRoundTrip], 사용자 결정 11-25). 손이 닿으면 그 자리에 멈추고, 동작 줄이기 ·
/// 앱 투어 중 · 밀 것이 없으면 움직이지 않는다.
class PollFeedTabs extends ConsumerStatefulWidget {
  const PollFeedTabs({required this.selected, required this.onSelected, super.key});

  /// 안내 움직임 왕복 시간(가기 절반 · 오기 절반). 폰에서 보고 빠르기를 고치면 이 한 줄만 바꾼다.
  static const Duration hintRoundTrip = Duration(seconds: 4);

  /// 화면이 뜨고 움직임이 시작되기까지(탭 전환이 끝난 뒤 보이게).
  static const Duration hintDelay = Duration(milliseconds: 400);

  /// 안내 움직임을 켤지. E2E 진입점(`integration_test/e2e_test.dart`)이 `app.main()` 전에 끈다 —
  /// 하네스는 가설마다 새 계정이라 움직이는 줄을 누르면 중간에 멈춰 다음 탭 찾기가 빗나갈 수 있다.
  static bool hintEnabled = true;

  final CommunityFeedTab selected;
  final ValueChanged<CommunityFeedTab> onSelected;

  /// 탭 하나의 누름 영역(72×86 전체). 시험이 자리 · 누름을 잰다.
  static Key tabKey(CommunityFeedTab tab) => Key('poll-feed-tab-${tab.name}');

  /// 탭의 고리(64). 시험이 선택 테두리를 본다.
  static Key ringKey(CommunityFeedTab tab) => Key('poll-feed-tab-ring-${tab.name}');

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xxs, AppSpacing.md, AppSpacing.sm);

  /// pen StoryStrip gap 4.
  static const double _gap = AppSpacing.xxs;

  /// 앱바 `bottom` 높이 — 위 4 + 탭(고리 + 6 + 글자 한 줄) + 아래 12. 1배면 102(pen `VEZ2l`).
  static double heightFor(TextScaler textScaler) => _padding.vertical + PollRingTab.heightFor(textScaler);

  /// 탭 줄에 보이는 탭 — 7개 전부, enum 순서가 pen 순서(전체 · 인기 · 내 글 · 내 투표 · 자유 · 진로 · 연애)다.
  static const List<CommunityFeedTab> shownTabs = CommunityFeedTab.values;

  static (String, AppIcon3d) _look(AppLocalizations l10n, CommunityFeedTab tab) => switch (tab) {
        CommunityFeedTab.all => (l10n.communityTabAll, AppIcon3d.vote), // 3D 투표 `x5QLa`
        CommunityFeedTab.popular => (l10n.communityTabPopular, AppIcon3d.sparkles), // 3D 반짝임 `ulHL7`
        CommunityFeedTab.mine => (l10n.communityTabMyPosts, AppIcon3d.userRound), // 3D 프로필 `PkqpC`
        CommunityFeedTab.voted => (l10n.communityTabVoted, AppIcon3d.badgeCheck), // 3D 인증 `Trtii`
        CommunityFeedTab.free => _category(l10n, CommunityCategory.free),
        CommunityFeedTab.career => _category(l10n, CommunityCategory.career),
        CommunityFeedTab.love => _category(l10n, CommunityCategory.love),
      };

  /// 카테고리 탭 글자 · 그림은 칩 · 라벨과 같은 한 곳([CommunityCategoryLook])에서 온다.
  static (String, AppIcon3d) _category(AppLocalizations l10n, CommunityCategory category) =>
      (category.label(l10n), category.icon);

  @override
  ConsumerState<PollFeedTabs> createState() => _PollFeedTabsState();
}

class _PollFeedTabsState extends ConsumerState<PollFeedTabs> with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  late final AnimationController _hint = AnimationController(vsync: this, duration: PollFeedTabs.hintRoundTrip);
  Timer? _start;

  /// 손이 한 번이라도 닿았다 — 그 뒤로는 이 화면에서 움직이지 않는다.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _start = Timer(PollFeedTabs.hintDelay, _play);
  }

  @override
  void dispose() {
    _start?.cancel();
    _hint.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _play() {
    if (!mounted || !PollFeedTabs.hintEnabled) return;
    if (_touched ||
        // 로그인 전(계정 모름)이면 커뮤니티가 아니다. 이 값을 덮지 않는 위젯 시험에서도 움직이지 않게 된다.
        ref.read(tourAccountIdProvider)() == null ||
        MediaQuery.disableAnimationsOf(context) ||
        ref.read(appTourViewModelProvider).active ||
        !_scroll.hasClients ||
        _scroll.position.maxScrollExtent <= 0) {
      return;
    }
    final end = _scroll.position.maxScrollExtent;
    final there = CurveTween(curve: AppMotion.floatCurve);
    final path = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: end).chain(there), weight: 1),
      TweenSequenceItem(tween: Tween(begin: end, end: 0.0).chain(there), weight: 1),
    ]).animate(_hint);
    path.addListener(() {
      if (_scroll.hasClients) _scroll.jumpTo(path.value);
    });
    unawaited(_hint.forward().orCancel.catchError((_) {}));
  }

  /// 손이 닿으면 그 자리에서 멈춘다(되돌리지 않는다). 시작 전이면 이 화면에선 시작하지 않는다.
  void _stop(PointerDownEvent _) {
    _touched = true;
    _start?.cancel();
    _hint.stop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = widget.selected;
    return Listener(
      onPointerDown: _stop,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: PollFeedTabs._padding,
        // 앱 투어 3단계가 이 줄을 가리킨다 — 표식은 자리 · 크기를 바꾸지 않는다.
        child: TourTarget(
            id: TourTargetId.communityTabs,
            child: Row(
              spacing: PollFeedTabs._gap,
              children: [
                for (final tab in PollFeedTabs.shownTabs)
                  PollRingTab(
                    tapKey: PollFeedTabs.tabKey(tab),
                    ringKey: PollFeedTabs.ringKey(tab),
                    label: PollFeedTabs._look(l10n, tab).$1,
                    icon: PollFeedTabs._look(l10n, tab).$2,
                    selected: tab == selected,
                    onTap: () => widget.onSelected(tab),
                  ),
              ],
            ),
        ),
      ),
    );
  }
}

/// 링 탭 하나(pen StoryTab `XfcKQ`): 72×86 · 세로 가운데 · 간격 6. 고리 64(테두리 2 · 안쪽 5 · 흰 바탕) 안에 원판 54(`primary-wash`)
/// 안에 3D 그림 28 가운데, 아래 글자 12. 선택 = 고리 `primary-rausch` + 글자 `primary-text` 700,
/// 나머지 = 고리 `hairline` + 글자 `body` 600. 15d 탭 줄과 17b 투표 방식 탭(pen `CgYsy`)이 같이 쓴다.
class PollRingTab extends StatelessWidget {
  const PollRingTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.tapKey,
    this.ringKey,
    super.key,
  });

  /// 누름 영역(72×86 전체) · 고리(64) — 시험이 자리 · 선택 테두리를 본다.
  final Key? tapKey;
  final Key? ringKey;
  final String label;
  final AppIcon3d icon;
  final bool selected;
  final VoidCallback onTap;

  static const double _width = 72;
  static const double _ring = 64;
  static const double _disk = 54;
  static const double _icon = 28;
  static const double _border = 2;

  /// pen 간격 6(토큰 밖).
  static const double _gap = 6;
  /// 글자 크기는 caption 토큰이 정한다(12) — 줄 높이 계산에만 다시 쓴다.
  static final double _fontSize = AppTypography.caption.fontSize!;

  /// 글자 줄 높이 16 — pen 탭 86 − 고리 64 − 간격 6 에서 나온 값(pen 은 글자 12 만 적었다).
  static const double _lineHeight = 16;

  /// 탭 높이 — 고리 + 6 + 글자 한 줄. 1배면 86.
  static double heightFor(TextScaler textScaler) =>
      _ring + _gap + textScaler.scale(_fontSize) * (_lineHeight / _fontSize);

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.caption.copyWith(
      height: _lineHeight / _fontSize,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      color: selected ? AppColors.primaryText : AppColors.body,
    );
    // 탭 줄이 가로로 밀린다 — 투명 Material 이 눌림 효과를 이 칸에 붙든다(COMMON §4-2).
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          key: tapKey,
          onTap: onTap,
          child: ConstrainedBox(
            // 글자를 키워 고리보다 넓어지면 탭이 따라 넓어진다(글자를 자르지 않는다).
            constraints: const BoxConstraints(minWidth: _width),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ringOf(icon),
                const SizedBox(height: _gap),
                Text(label, style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ringOf(AppIcon3d icon) => Container(
        key: ringKey,
        width: _ring,
        height: _ring,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.canvas,
          border: Border.all(color: selected ? AppColors.primary : AppColors.hairline, width: _border),
        ),
        // 테두리 2 안쪽에서 가운데 — 고리 가장자리에서 5 떨어진 54 원판.
        child: SizedBox.square(
          dimension: _disk,
          child: DecoratedBox(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryWash),
            child: Center(child: Icon3d(icon, size: _icon)),
          ),
        ),
      );
}
