import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 그림 자리 44 안에 3D 그림 40(pen `BeClX`).
const double _artSlot = 44;
const double _artSize = 40;

/// 그림 · 숫자 · 라벨 사이(pen `BeClX` gap 2)
const double _gap = 2;

/// 6칸 그리드 위 행 통계 한 칸 — pen HomeTileGrid v2 `R62HQ` 의 통계 칸 마스터 `BeClX`(이름 대응: HomeStatsTile, 10-16 초안 A). 누르지 않는다.
/// canvas · 모서리 14 · 테두리 없음 · 바깥 그림자 [AppElevation.homeTileLow] · 최소 높이 112 · 좌우 4.
/// 세로 가운데 gap 2: 그림 자리 44(3D 그림 40) → 숫자 24/700 primaryText 자간 −0.3(33) → 라벨 12/600 muted(17).
/// 통합 시험(area2 E-HOME-02)이 [label] · [value] 를 그대로 읽는다 — 이름을 바꾸지 않는다.
class StatTile extends StatelessWidget {
  const StatTile({required this.icon, required this.value, required this.label, super.key});

  final AppIcon3d icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    // 112 는 최소 높이다 — 글자를 키우면 늘어나고, 라벨은 줄을 바꾼다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppElevation.homeTileLow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: _artSlot, height: _artSlot, child: Center(child: Icon3d(icon, size: _artSize))),
          const SizedBox(height: _gap),
          // 숫자가 길어져도 줄을 바꾸지 않고 칸 안에서 줄인다. softWrap 을 꺼야 IntrinsicHeight 가 두 줄로 세지 않는다.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              softWrap: false,
              // 글자 상자 33 — headline 토큰 줄높이 1.35(32.4)와 달라 맞춘다. 자간 −0.3 은 pen 값(토큰 −0.48 과 다르다).
              style: AppTypography.headline.copyWith(height: 33 / 24, letterSpacing: -0.3, color: AppColors.primaryText),
            ),
          ),
          const SizedBox(height: _gap),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 17 / 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// 6칸 그리드 링크 · 곧 열려요 칸의 그림 원: 40 · surfaceSoft 채움 · 테두리 · 그림자 없음(pen `F4rC8g` · `BoTMl`, 10-16 초안 A).
/// 통계 칸은 이 원 없이 그림만 둔다.
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
