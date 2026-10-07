import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 번들 카드 한 장(pen `w0vIYG` HeartBundleCard 328×88). 고른 카드는 바탕 primaryWash · 테두리 2px primary(`J0o8uB`).
/// 테두리는 안쪽에 덧그려서 고르고 말 때 안의 글자가 움직이지 않는다.
class HeartBundleCard extends StatelessWidget {
  const HeartBundleCard({required this.bundle, required this.selected, required this.onTap, super.key});

  final HeartBundle bundle;
  final bool selected;
  final VoidCallback onTap;

  static const double _maxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: _semanticsLabel,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: selected ? AppColors.primaryWash : AppColors.canvas,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 88),
                padding: const EdgeInsets.all(AppSpacing.md),
                foregroundDecoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.hairlineSoft,
                    width: selected ? 2 : 1,
                  ),
                ),
                // 카드 폭 328 은 고정이라 글자 배율은 [_maxTextScale] 까지만 따른다(그 이상이면 가격 · 할인이 한 줄에 안 든다).
                // 수량은 남는 폭에 맞춰 줄어든다 — 가격 · 할인율이 잘리면 안 된다.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _maxTextScale,
                  child: Row(
                    children: [
                      Image.asset(bundle.asset, width: 56, height: 56, fit: BoxFit.cover, excludeFromSemantics: true),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(bundle.quantityLabel, style: AppTypography.title.copyWith(color: AppColors.ink)),
                        ),
                      ),
                      // 수량 · 할인 · 가격 사이는 모두 12(pen Info ↔ Discount ↔ PriceCol gap).
                      const SizedBox(width: AppSpacing.sm),
                      if (bundle.discountPercent != null) ...[
                        _Discount(bundle: bundle),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      _PriceColumn(bundle: bundle),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 추천 태그 `Fs0PO` — 카드 위 끝에 걸친다(x16 · y−9, 높이 18, 좌우 8).
          if (bundle.isRecommended) const Positioned(left: AppSpacing.md, top: -9, child: _RecommendTag()),
        ],
      ),
    );
  }

  String get _semanticsLabel {
    final parts = [
      bundle.quantityLabel,
      '${formatWon(bundle.price)}원',
      if (bundle.discountPercent != null) '${bundle.discountPercent}퍼센트 할인',
      if (bundle.isMaxDiscount) '최대 할인',
      if (bundle.isRecommended) '추천',
    ];
    return parts.join(', ');
  }
}

/// 할인율(`AEAAV`): "최대 할인"(`wWEMu` 11/600) 위에 "5%"(`wUXqw` 17/600) — 둘 다 primaryText, 오른쪽 정렬.
class _Discount extends StatelessWidget {
  const _Discount({required this.bundle});

  final HeartBundle bundle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (bundle.isMaxDiscount) Text('최대 할인', style: AppTypography.badge.copyWith(color: AppColors.primaryText)),
        Text('${bundle.discountPercent}%', style: AppTypography.subtitle.copyWith(color: AppColors.primaryText)),
      ],
    );
  }
}

/// 가격(`u0SF9`): "3,000원" 18/700 ink, 그 아래 할인 전 "원가 6,000원" 12 muted(값만 취소선).
class _PriceColumn extends StatelessWidget {
  const _PriceColumn({required this.bundle});

  final HeartBundle bundle;

  @override
  Widget build(BuildContext context) {
    final original = bundle.originalPrice;
    final muted = AppTypography.caption.copyWith(color: AppColors.muted);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${formatWon(bundle.price)}원', style: AppTypography.subNavTitle.copyWith(color: AppColors.ink)),
        if (original != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('원가', style: muted),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                '${formatWon(original)}원',
                style: muted.copyWith(decoration: TextDecoration.lineThrough, decorationColor: AppColors.disabled),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// "추천"(`Fs0PO` = CountBadge 변형: 높이 18 · 좌우 8 · primary 채움 · 글자 11/600 흰색).
class _RecommendTag extends StatelessWidget {
  const _RecommendTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text('추천', style: AppTypography.badge.copyWith(color: AppColors.onInk, height: 1.0)),
    );
  }
}
