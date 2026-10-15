import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/tour_target.dart';
import 'package:flutter/material.dart';

/// 15d 탭 줄(pen `VEZ2l` StoryStrip): 폭 꽉 · 안쪽 [4,16,12,16] · 탭 4개(`XfcKQ` 72×86) 양끝 맞춤(space_between) ·
/// 바탕 투명(뒤 canvas 흰) · 아래 구분선 없음. 앱바 `bottom` 에 꽂아 목록과 같이 스크롤되지 않는다 — 높이는 [heightFor].
/// 글자를 키워 화면보다 넓어지면 가로로 민다(사용자 결정, 조사 보고 추천안).
class PollFeedTabs extends StatelessWidget {
  const PollFeedTabs({required this.selected, required this.onSelected, super.key});

  final PollFeedTab selected;
  final ValueChanged<PollFeedTab> onSelected;

  /// 탭 하나의 누름 영역(72×86 전체). 시험이 자리 · 누름을 잰다.
  static Key tabKey(PollFeedTab tab) => Key('poll-feed-tab-${tab.name}');

  /// 탭의 고리(64). 시험이 선택 테두리를 본다.
  static Key ringKey(PollFeedTab tab) => Key('poll-feed-tab-ring-${tab.name}');

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xxs, AppSpacing.md, AppSpacing.sm);

  /// 글자 2배처럼 탭이 넓어져 서로 붙을 때만 드러나는 최소 틈. **pen 에 없는 값** —
  /// 1배 360 폭의 틈은 (328 − 72 × 4) / 3 ≈ 13.3 이라 이 값이 배치를 바꾸지 않는다.
  static const double _minGap = AppSpacing.xs;

  /// 앱바 `bottom` 높이 — 위 4 + 탭(고리 + 6 + 글자 한 줄) + 아래 12. 1배면 102(pen `VEZ2l`).
  static double heightFor(TextScaler textScaler) => _padding.vertical + _Tab.heightFor(textScaler);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: _padding,
        child: ConstrainedBox(
          // 넓으면 남는 폭을 탭 사이에 똑같이 나누고(space_between), 모자라면 그대로 이어 붙여 가로로 민다.
          constraints: BoxConstraints(minWidth: constraints.maxWidth - _padding.horizontal),
          // 앱 투어 3단계가 이 줄(탭 4개)을 가리킨다 — 표식은 자리 · 크기를 바꾸지 않는다.
          child: TourTarget(
            id: TourTargetId.communityTabs,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: _minGap,
              children: [
                for (final tab in PollFeedTab.values)
                  _Tab(
                    tapKey: tabKey(tab),
                    ringKey: ringKey(tab),
                    tab: tab,
                    selected: tab == selected,
                    onTap: () => onSelected(tab),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 탭 하나(pen `XfcKQ`): 72×86 · 세로 가운데 · 간격 6. 고리 64(테두리 2 · 안쪽 5 · 흰 바탕) 안에 원판 54(`primary-wash`)
/// 안에 3D 그림 28 가운데, 아래 글자 12. 선택 = 고리 `primary-rausch` + 글자 `primary-text` 700,
/// 나머지 = 고리 `hairline` + 글자 `body` 600.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.tapKey,
    required this.ringKey,
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final Key tapKey;
  final Key ringKey;
  final PollFeedTab tab;
  final bool selected;
  final VoidCallback onTap;

  static const double _width = 72;
  static const double _ring = 64;
  static const double _disk = 54;
  static const double _icon = 28;
  static const double _border = 2;

  /// pen 간격 6(토큰 밖).
  static const double _gap = 6;
  static const double _fontSize = 12;

  /// 글자 줄 높이 16 — pen 탭 86 − 고리 64 − 간격 6 에서 나온 값(pen 은 글자 12 만 적었다).
  static const double _lineHeight = 16;

  static double heightFor(TextScaler textScaler) =>
      _ring + _gap + textScaler.scale(_fontSize) * (_lineHeight / _fontSize);

  (String, AppIcon3d) get _look => switch (tab) {
        PollFeedTab.all => ('전체', AppIcon3d.vote), // 3D 투표 `x5QLa`
        PollFeedTab.popular => ('인기', AppIcon3d.sparkles), // 3D 반짝임 `ulHL7`
        PollFeedTab.mine => ('내 질문', AppIcon3d.userRound), // 3D 프로필 `PkqpC`
        PollFeedTab.voted => ('내 투표', AppIcon3d.badgeCheck), // 3D 인증 `Trtii`
      };

  @override
  Widget build(BuildContext context) {
    final (label, icon) = _look;
    final style = AppTypography.caption.copyWith(
      fontSize: _fontSize,
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
