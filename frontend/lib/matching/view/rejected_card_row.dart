import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/matching/model/data/rejected_card.dart';
import 'package:campus_mate/matching/view/row_with_actions.dart';
import 'package:campus_mate/matching/view/sent_request_row.dart';
import 'package:flutter/material.dart';

/// 거절한 카드 한 줄(pen `pdOvf` RejectedCardRow, 대화 탭 [거절한 카드] lmwl8). 보낸 신청 줄 틀(d6otzp) → 12 →
/// [프로필 보기](보조 surface-strong · ink) + 오른쪽 버튼(primary) — 내 카드를 넘긴 줄은 [다시 신청하기], 받은 신청을 거절한 줄은
/// [수락하기](pen wqlyd). 두 버튼은 AppButton 작은 크기(44 · 모서리 8 · 18/700, 대장 판정 6).
/// 칩은 서버의 남은 날([RejectedCard.daysLeft]) 그대로다 — 앱이 날짜를 다시 재지 않는다. 1 이면 "오늘 마감" 을 강조색으로.
/// 줄 자체는 눌리지 않는다(pen 에 줄 눌림이 없다).
class RejectedCardRow extends StatelessWidget {
  const RejectedCardRow({
    required this.card,
    required this.onViewProfile,
    required this.onAction,
    this.isSubmitting = false,
    super.key,
  });

  final RejectedCard card;
  final VoidCallback onViewProfile;

  /// [다시 신청하기] · [수락하기]. null 이면 꺼진다(다른 줄을 보내는 중).
  final VoidCallback? onAction;

  /// 이 줄을 보내는 중 — 오른쪽 버튼이 도는 표시가 된다.
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RowWithActions(
      // 줄 → 버튼 띠 12(pen pdOvf 세로 gap 12).
      gap: AppSpacing.sm,
      row: RequestRowFrame(
        profile: card.profile,
        // 칩 아이콘은 pen 에 따로 적혀 있지 않아 보낸 신청 "N일 남음" 칩과 같은 타이머다.
        status: RequestStatusChip(
          icon: AppIcons.timer,
          label: daysLeftLabel(l10n, card.daysLeft),
          highlighted: card.daysLeft <= 1,
        ),
      ),
      actions: [
        AppButton(
          label: l10n.matchingAcceptanceRowViewProfile,
          variant: AppButtonVariant.tonal,
          size: AppButtonSize.small,
          onPressed: onViewProfile,
        ),
        AppButton(
          label: switch (card.source) {
            RejectedSource.card => l10n.matchingRejectedReapply,
            RejectedSource.acceptance => l10n.matchingAcceptanceDetailAccept,
          },
          size: AppButtonSize.small,
          isLoading: isSubmitting,
          onPressed: onAction,
        ),
      ],
    );
  }
}
