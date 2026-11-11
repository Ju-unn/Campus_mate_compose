import 'package:campus_mate/common/widgets/alert_sheet.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 삭제 확인 시트(pen AlertSheet `D0TvG` — 글 · 댓글 15d-2 · 쓴 리뷰 20e-2 가 같은 마스터).
/// 제목 20/700 → 16 → 설명 14 muted → 16 → 확인(danger 52) → 8 → 취소(text 48). 문구는 호출쪽이 넘긴다.
/// 지우는 중(`EIEFb`)엔 확인 버튼만 꺼진 회색이 되고(도는 표시 없음) "취소" · 바깥 탭은 그대로 닫는다.
/// [onDelete] 가 끝나면 시트를 닫는다. 실패 알림 · 토스트는 호출쪽이 [onDelete] 안에서 정한다.
class DeleteConfirmSheet extends StatefulWidget {
  const DeleteConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.onDelete,
    super.key,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final Future<void> Function() onDelete;

  @override
  State<DeleteConfirmSheet> createState() => _DeleteConfirmSheetState();
}

class _DeleteConfirmSheetState extends State<DeleteConfirmSheet> {
  bool _deleting = false;

  Future<void> _delete() async {
    setState(() => _deleting = true);
    await widget.onDelete();
    // "취소" · 바깥 탭으로 이미 닫히는 중이면(애니메이션 동안 State 는 살아 있다) 또 닫지 않는다 — 밑 화면이 닫힌다.
    if (mounted && (ModalRoute.isCurrentOf(context) ?? false)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertSheet(
      children: [
        Text(widget.title, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.md),
        Text(widget.body, style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: widget.confirmLabel,
          variant: AppButtonVariant.danger,
          onPressed: _deleting ? null : _delete,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          label: context.l10n.commonCancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
