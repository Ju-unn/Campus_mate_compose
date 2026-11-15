import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 09b 링크 칸 줄 — pen 홈 시안 A `TdmIQ`(2026-11-16 사용자 「A로 하고」): 인스타그램 · 문의하기 2칸이 반반, 사이 8, 높이 80
/// (앱은 화면 폭에 맞춘다). 문의하기는 11-12 의 에브리타임 칸 자리다(사용자 「메인에 … "에브리타임" -> 삭제」).
/// 감싸는 바탕 · 여백은 없고 칸마다 흰 바탕을 칠한다(링크 칸 `F4rC8g`). 요약이 없으면(조회 중 · 실패) 홈 화면이 통째로 숨긴다.
class HomeGrid extends StatelessWidget {
  const HomeGrid({required this.onInstagram, required this.onInquiry, super.key});

  final VoidCallback onInstagram;

  /// 앱 안 문의하기 화면(`/settings/inquiry`)으로 간다.
  final VoidCallback onInquiry;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      // 글자를 키워 한 칸이 늘어나면 옆 칸 높이도 같이 맞춘다.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _LinkTile(
              art: _logo('assets/images/brand-instagram-v1.webp'),
              label: context.l10n.homeGridInstagram,
              semanticLabel: context.l10n.homeGridInstagramSemantics,
              onTap: onInstagram,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _LinkTile(
              // pen `Rb8A3` 3D help — 인스타그램 로고와 같은 28.
              art: const Icon3d(AppIcon3d.help, size: _artSize),
              label: context.l10n.homeGridInquiry,
              semanticLabel: context.l10n.homeGridInquiry,
              onTap: onInquiry,
              // 앱 안 화면으로 가니 "밖으로" 칩을 달지 않는다.
              external: false,
            ),
          ),
        ],
      ),
    );
  }

  /// 링크 칸 그림 28(그림 원 40 안, 두 칸 같은 크기).
  static const double _artSize = 28;

  static Widget _logo(String asset) => Image.asset(asset, width: _artSize, height: _artSize, fit: BoxFit.contain);
}

/// 링크 칸 최소 높이(pen `C3J23d` 링크 행 80) — 글자를 키우면 늘어난다.
const double _linkRowMinHeight = 80;

/// 그림 원과 라벨 사이(pen `F4rC8g` gap 6)
const double _plateLabelGap = 6;

/// 링크 칸(인스타그램 · 문의하기) — pen 링크 칸 마스터 `F4rC8g`(이름 대응: HomeLinkTile). 칸 전체가 누름 칸이고 잉크는 칸 자기 Material 에
/// 그린다 — 홈 목록 안에서 움직이므로(COMMON 4-2). canvas · 안쪽 hairline 1 테두리 · 모서리 14 · 바깥 그림자 [AppElevation.homeTileRaised].
/// 그림 원 40 → 6 → 라벨 12/600 ink lh1.4 를 세로 가운데, 앱 밖으로 가는 칸([external])만 오른쪽 위(위 6 · 오른쪽 6)에 화살표 칩.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.art,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.external = true,
  });

  final Widget art;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool external;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      // 그림자는 Material 밖 상자가 그린다 — Material elevation 그림자는 pen 값과 다르다.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppElevation.homeTileRaised,
        ),
        child: Material(
          color: AppColors.canvas,
          // BorderSide 는 기본이 안쪽 선이다 — 칸 크기 그대로 테두리를 그린다.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _linkRowMinHeight),
              // 글 칸은 위치를 주지 않는 자식이라야 줄 높이(IntrinsicHeight)에 들어간다 — 글자를 키우면 칸이 늘어난다.
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _PlateAndLabel(
                    plate: art,
                    label: Text(
                      label,
                      softWrap: false,
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 1.4, color: AppColors.ink),
                    ),
                  ),
                  if (external) const Positioned(top: 6, right: 6, child: _ArrowChip()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 링크 칸 오른쪽 위 "다른 곳으로" 칩 — 20 원 primaryWash 안에 arrow-up-right 12 primaryText(pen `F4rC8g`).
class _ArrowChip extends StatelessWidget {
  const _ArrowChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
      child: const Icon(AppIcons.arrowUpRight, size: 12, color: AppColors.primaryText),
    );
  }
}

/// 링크 칸 속: 그림 원 40 → 6 → 라벨, 좌우 4. 한 낱말 라벨이라 줄을 바꿀 곳이 없다 —
/// 글자를 키워 칸보다 넓어지면 자르지 않고 줄인다.
class _PlateAndLabel extends StatelessWidget {
  const _PlateAndLabel({required this.plate, required this.label});

  final Widget plate;
  final Text label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconPlate(child: plate),
          const SizedBox(height: _plateLabelGap),
          FittedBox(fit: BoxFit.scaleDown, child: label),
        ],
      ),
    );
  }
}

/// 링크 칸의 그림 원: 40 · surfaceSoft 채움 · 테두리 · 그림자 없음(pen `F4rC8g`).
class IconPlate extends StatelessWidget {
  const IconPlate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.surfaceSoft, shape: BoxShape.circle),
      child: child,
    );
  }
}
