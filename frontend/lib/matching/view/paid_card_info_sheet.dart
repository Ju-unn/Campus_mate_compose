import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/sheet_handle.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// "이렇게 정밀하게 골랐어요" 의 이유 넷(pen 값표 §6). 앱 투어 5단계(`tour/view/tour_precision_points.dart`)도 같은 이름 · 그림을 쓴다 —
/// 한쪽만 바뀌지 않게 여기 한 곳에 둔다(글자는 문구 파일 ARB `matchingPaidReason*`).
List<({AppIcon3d icon, String title, String description})> paidCardReasons(AppLocalizations l10n) => [
      (
        icon: AppIcon3d.chat,
        title: l10n.matchingPaidReasonTraitsTitle,
        description: l10n.matchingPaidReasonTraitsDescription,
      ),
      (icon: AppIcon3d.tags, title: l10n.matchingPaidReasonTagsTitle, description: l10n.matchingPaidReasonTagsDescription),
      (icon: AppIcon3d.sparkles, title: l10n.matchingPaidReasonTextTitle, description: l10n.matchingPaidReasonTextDescription),
      (
        icon: AppIcon3d.badgeCheck,
        title: l10n.matchingPaidReasonConditionsTitle,
        description: l10n.matchingPaidReasonConditionsDescription,
      ),
    ];

/// 결제 카드 물음표를 누르면 뜨는 "이렇게 정밀하게 골랐어요" 안내 시트(pen `EP8pA` → 시트 `sp1xa`, 값표 §6).
/// 문구는 pen 값표 그대로이고, 점수 숫자 · 순위 · 비중(30/20/50%) · 학교 이름은 이 시트에 없다.
Future<void> showPaidCardInfoSheet(BuildContext context) {
  return showSafetySheet<void>(context, (_) => const PaidCardInfoSheet());
}

/// 시트 틀은 안전 시트(`SafetySheet`, 여백 [12,20,28,20])와 안쪽 여백이 달라 따로 그린다.
/// pen: 손잡이 칸 28(padding [12,0]) + 내용 padding [8,16,32,16], 세로 gap 16.
/// 글자를 키우면 시트가 화면보다 길어지니 안쪽을 스크롤로 둔다.
class PaidCardInfoSheet extends StatelessWidget {
  const PaidCardInfoSheet({super.key});

  /// pen `sXtnP` 의 gap.
  static const double _gap = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      key: const ValueKey('paid-card-info-sheet'),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // `NB9LG` 손잡이 칸 360×28 — 손잡이 `EOSt5` 36×4 가 위에서 12.
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(child: SheetHandle(key: ValueKey('paid-card-info-handle'))),
              ),
              Padding(
                // pen `sXtnP` padding [8,16,32,16].
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // pen `aaNm1` 20/700, 줄높이 속성 없음 · 렌더 29.
                    Text(
                      l10n.matchingPaidInfoTitle,
                      style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20),
                    ),
                    const SizedBox(height: _gap),
                    // pen `du9NW` 14/400/1.55 #6A6A6A.
                    Text(
                      l10n.matchingPaidInfoBody,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                    ),
                    for (final reason in paidCardReasons(l10n)) ...[
                      const SizedBox(height: _gap),
                      _ReasonRow(icon: reason.icon, title: reason.title, description: reason.description),
                    ],
                    const SizedBox(height: _gap),
                    const _Highlight(),
                    const SizedBox(height: _gap),
                    KeyedSubtree(
                      key: const ValueKey('paid-card-info-confirm'),
                      child: AppButton(
                        label: l10n.matchingPaidInfoConfirm,
                        trailingIcon: AppIcons.arrowRight,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 이유 한 줄(pen `musvL` 등) — 아이콘 36×36, 글 상자는 오른쪽 12, 제목과 설명 사이 2.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.icon, required this.title, required this.description});

  final AppIcon3d icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon3d(icon, size: 36),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // pen 16/700/1.4 #222222 — bodyStrong(16/600)에서 굵기만 올린다.
              Text(
                title,
                style: AppTypography.bodyStrong.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              // pen 14/normal/1.45 #6A6A6A.
              Text(description, style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}

/// `vMtVN` 강조 상자 — padding 14, 모서리 12, 채움 primary-wash. 안의 숨은 링크 잔재(`vI8C0`)는 옮기지 않는다.
class _Highlight extends StatelessWidget {
  const _Highlight();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('paid-card-info-highlight'),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          context.l10n.matchingPaidInfoHighlight,
          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 1.5, color: AppColors.ink),
        ),
      ),
    );
  }
}
