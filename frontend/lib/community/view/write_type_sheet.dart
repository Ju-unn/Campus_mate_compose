import 'package:campus_mate/common/widgets/alert_sheet.dart';
import 'package:campus_mate/common/widgets/app_bottom_sheet.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// "글쓰기" 알약을 누르면 뜨는 고르기 시트(pen 17 `LSCrq`). 고른 종류를 돌려준다(그냥 닫으면 null).
Future<CommunityKind?> showWriteTypeSheet(BuildContext context) => showAppBottomSheet<CommunityKind>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const WriteTypeSheet(),
    );

/// pen WriteTypeSheet `ELuBm`(360×282): AlertSheet 모양(`S2oym` — 손잡이 칸 28 · 내용 [8,16,32,16])에
/// 제목 "무엇을 올릴까요?" 20/700 → 16 → 줄 둘(76, 사이 16). 높이 = 28 + 8 + 30 + 16 + 76 + 16 + 76 + 32 = 282.
class WriteTypeSheet extends StatelessWidget {
  const WriteTypeSheet({super.key});

  /// 줄 하나의 누름 영역(328×76). 시험이 자리를 잰다.
  static Key rowKey(CommunityKind kind) => Key('write-type-${kind.name}');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertSheet(
      children: [
        // pen `rFp47` 20/700 lh1.5 ls-0.4 ink = navTitle.
        Text(l10n.communityWriteTypeTitle, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.md),
        _TypeRow(
          kind: CommunityKind.poll,
          icon: const Icon3d(AppIcon3d.vote, size: 48), // 3D 투표 `x5QLa`
          title: l10n.communityComposerKindPoll,
          note: l10n.communityComposerKindPollNote,
        ),
        const SizedBox(height: AppSpacing.md),
        _TypeRow(
          kind: CommunityKind.post,
          icon: const Icon3d(AppIcon3d.pencil, size: 36), // 3D 편집 `DAILv`
          title: l10n.communityComposerKindPost,
          note: l10n.communityComposerKindPostNote,
        ),
      ],
    );
  }
}

/// 줄 하나(pen `xedYu` · `Qrwo9`): surface-soft · 모서리 md · 안쪽 [0,16] · 간격 14 —
/// 아이콘 칸 52(canvas · 모서리 md) → 제목 16/700 lh1.4 ink · 설명 14/400 lh1.5 muted → chevron-right 20 muted.
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.kind, required this.icon, required this.title, required this.note});

  final CommunityKind kind;
  final Widget icon;
  final String title;
  final String note;

  /// pen gap 14 — 간격 토큰 sm(12) · md(16) 사이 값.
  static const double _gap = 14;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
    return Material(
      color: AppColors.surfaceSoft,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: WriteTypeSheet.rowKey(kind),
        onTap: () => Navigator.of(context).pop(kind),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: icon,
                ),
                const SizedBox(width: _gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, height: 1.4, color: AppColors.ink)),
                      Text(note, style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: _gap),
                const Icon(AppIcons.chevronRight, size: 20, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
