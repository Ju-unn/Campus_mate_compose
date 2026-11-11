import 'package:campus_mate/common/widgets/reason_radio_row.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/view/inquiry_reason_text.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 문의 사유 시트(pen 21b `Ywu44`)를 띄운다. "선택하기" 로 닫으면 고른 사유를, 취소 · 바깥 탭이면 null 을 돌려준다.
/// [current] 가 있으면 그 사유가 골라진 채로 열린다.
Future<InquiryReason?> showInquiryReasonSheet(BuildContext context, {InquiryReason? current}) {
  return showSafetySheet<InquiryReason>(context, (_) => InquiryReasonSheet(current: current));
}

/// 사유 시트 본문. 신고 시트(`yl8gX`)와 같은 틀 · 라디오 줄 · 버튼 두 개다 — pen 도 같은 모양으로 그렸다(대장 판단).
/// 고르는 것은 "선택하기" 를 눌러야 화면에 들어간다.
class InquiryReasonSheet extends StatefulWidget {
  const InquiryReasonSheet({this.current, super.key});

  final InquiryReason? current;

  @override
  State<InquiryReasonSheet> createState() => _InquiryReasonSheetState();
}

class _InquiryReasonSheetState extends State<InquiryReasonSheet> {
  late InquiryReason? _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return SafetySheet(
      children: [
        // pen `K2V9Ua` 18/700 / 줄높이 1.2.
        Text(
          context.l10n.inquiryReasonSheetTitle,
          style: AppTypography.label.copyWith(color: AppColors.ink, height: 1.2),
        ),
        // pen 사유 영역 `TvzEb` 세로 간격 4. 목록 `X2Ozb` 는 행 48 × 6, 간격 0.
        const SizedBox(height: AppSpacing.xxs),
        for (final reason in InquiryReason.values)
          ReasonRadioRow(
            label: reason.label(context.l10n),
            isSelected: selected == reason,
            onTap: () => setState(() => _selected = reason),
          ),
        // pen 은 사유 영역과 버튼 사이에 4px 투명 사각형(`hwAjp`)을 끼워 16 + 4 + 16 = 36 을 만든다.
        const SizedBox(height: 36),
        SafetySheetButton.primary(
          label: context.l10n.inquiryReasonSheetConfirm,
          onPressed: selected == null ? null : () => Navigator.of(context).pop(selected),
        ),
        const SizedBox(height: AppSpacing.md),
        SafetySheetButton.neutral(label: context.l10n.commonCancel, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
