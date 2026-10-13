import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/view/heart_purchase_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 하단 구매바(pen `GG0ei` HeartPurchaseBar 360×88). 고른 번들 이름(추천이면 위에 "추천")과 구매 버튼(`ipbPs`).
/// 흰 바탕 · 위쪽 선 1px #EBEBEB · 안쪽 [12,16,24,16] · 간격 12. 기기 아래 여백은 그 밑에 더한다.
/// 버튼 글자 · 진행 표시는 상점이 정한다(15e-1 "100하트 받기 · 5,700원" · 15e-3 "결제 확인 중이에요" · 15e-6 · 15e-7).
/// [onPurchase] 가 null 이면 버튼이 회색으로 꺼진다.
class HeartPurchaseBar extends StatelessWidget {
  const HeartPurchaseBar({
    required this.bundle,
    required this.buttonLabel,
    required this.onPurchase,
    this.busy = false,
    super.key,
  });

  final HeartBundle bundle;
  final String buttonLabel;
  final VoidCallback? onPurchase;
  final bool busy;

  /// 버튼이 차지할 수 있는 최대 몫. 글자를 크게 키우면 버튼 글자는 이 안에서 줄어들고, 번들 이름 칸이 남는다.
  static const double _buttonShare = 0.7;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Expanded(child: _Info(bundle: bundle)),
                  const SizedBox(width: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: (constraints.maxWidth - AppSpacing.sm) * _buttonShare),
                    child: HeartPurchaseButton(label: buttonLabel, busy: busy, onPressed: onPurchase),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `W9Ha4P`: "추천" 12/400 primaryText + 이름 16/600 ink. 좁아지면 줄여 넣는다(자르지 않는다).
class _Info extends StatelessWidget {
  const _Info({required this.bundle});

  final HeartBundle bundle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bundle.isRecommended)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('추천', style: AppTypography.caption.copyWith(color: AppColors.primaryText)),
          ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(bundle.quantityLabel, style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 1.5)),
        ),
      ],
    );
  }
}
