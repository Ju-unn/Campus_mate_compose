import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/view/paid_card_locked.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 결제 카드를 열기 전 확인 — 공용 확인 팝업 일반 변형(대장 전달 2026-11-16). 열기로 했으면 true, 취소 · 바깥 누름은 false.
/// 설명은 두 문장 한 키(사용자 「문구 너무 많아 … 정도로만」 · 「줄바꿈 하기」), 확인 라벨 앞에 하트 글리프 22(pen 값표).
Future<bool> showPaidCardConfirmPopup(BuildContext context, {required int cost}) => showConfirmPopup(
      context,
      title: context.l10n.matchingPaidConfirmTitle,
      body: context.l10n.matchingPaidConfirmBody(cost: cost),
      confirmLabel: context.l10n.matchingPaidConfirmCta(cost: cost),
      // pen 확인 팝업 값표: 하트 글리프 22(카드 자리의 26 과 다르다).
      confirmLeading: const PaidCardHeart(size: 22),
    );

/// 열기가 402(하트 부족)로 막혔을 때의 시트. 하트 스토어로 가려면 true, 닫기 · 바깥 누름은 false.
/// 제목은 서버 HEARTS_NOT_ENOUGH 와 같은 글자다. pen 에 전용 시트가 없어(값표 §8) 확인 시트와 같은 틀을 쓴다.
Future<bool> showPaidCardHeartsShortSheet(
  BuildContext context, {
  required int cost,
  required int? heartBalance,
}) async {
  final l10n = context.l10n;
  final goToStore = await showSafetySheet<bool>(
    context,
    (_) => _PaidCardSheet(
      title: l10n.commonHeartsShortTitle,
      description: heartBalance == null
          ? l10n.matchingPaidHeartsShortBody(cost: cost)
          : l10n.commonHeartsShortBodyWithBalance(cost: cost, balance: heartBalance),
      primaryLabel: l10n.matchingPaidHeartsShortCta,
      secondaryLabel: l10n.commonClose,
    ),
  );
  return goToStore ?? false;
}

class _PaidCardSheet extends StatelessWidget {
  const _PaidCardSheet({
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  final String title;
  final String description;
  final String primaryLabel;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return SafetySheet(
      children: [
        // pen `GZRVW` 20/700 #222222, 줄높이 속성 없음 · 렌더 29.
        Text(title, style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20)),
        const SizedBox(height: AppSpacing.md),
        // pen `g5RAq0` 16/400/1.5 #3F3F3F.
        Text(description, style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5)),
        // pen 은 설명과 버튼 사이에 투명 4(`keBbl`)를 끼워 16 + 4 + 16 = 36.
        const SizedBox(height: 36),
        SafetySheetButton.primary(label: primaryLabel, onPressed: () => Navigator.of(context).pop(true)),
        const SizedBox(height: AppSpacing.md),
        SafetySheetButton.neutral(label: secondaryLabel, onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
