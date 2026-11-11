import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/line_break_limit_formatter.dart';
import 'package:campus_mate/common/widgets/reason_radio_row.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/model/data/report_reason.dart';
import 'package:campus_mate/safety/model/data/report_target.dart';
import 'package:campus_mate/safety/view/report_reason_text.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/report_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시트가 닫히며 돌려주는 결과. 부른 쪽이 토스트(`showSafetyToast`)로 띄운다 — 신고됨(`ReportOutcome.reported`)이면
/// [failure] 가 null 이고 글자는 `safetyReported`, 아니면 [failure] 를 `failureText` 로 글자로 바꾼다.
typedef ReportSheetResult = ({ReportOutcome outcome, Failure? failure});

/// 기타 메모 상자. 테스트가 pen 크기(320×104)를 재는 데 쓴다.
const Key reportNoteBoxKey = ValueKey('report-note-box');

/// 신고 시트(pen `yl8gX`)를 띄운다. 끝난 결과(신고됨 · 이미 신고 · 하루 상한 · 대상 없음)면 그것을,
/// 취소 · 바깥 탭이면 null 을 돌려준다. 다시 보내야 하는 실패는 시트 안에서 끝난다.
Future<ReportSheetResult?> showReportSheet(BuildContext context, ReportTarget target) {
  return showSafetySheet<ReportSheetResult>(context, (_) => ReportSheet(target: target));
}

/// 신고 시트 본문. 상태는 [reportViewModelProvider] 가 들고, 시트는 결과가 나오면 닫기만 한다.
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({required this.target, super.key});

  final ReportTarget target;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  // 기타에서 다른 사유로 옮겼다 돌아와도 쓴 글이 남는다 — 뷰모델도 메모를 비우지 않는다.
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportViewModelProvider);
    final viewModel = ref.read(reportViewModelProvider.notifier);
    ref.listen(reportViewModelProvider, (previous, next) {
      final outcome = next.outcome;
      if (outcome == null || previous?.outcome != null) {
        return;
      }
      Navigator.of(context).pop((outcome: outcome, failure: next.closingFailure));
    });
    final isOther = state.selectedReason == ReportReason.other;
    return SafetySheet(
      children: [
        // pen `sGjsm` 18/700, 줄높이 속성 없음 · 렌더 26.
        Text(
          context.l10n.safetyReportTitle,
          style: AppTypography.label.copyWith(color: AppColors.ink, height: 26 / 18),
        ),
        // pen 사유 영역 `QMdpZ` 세로 간격 4(제목 · 목록 · 입력칸 사이). 목록 `MY7UX` 은 행 48 × 5, 간격 0.
        const SizedBox(height: AppSpacing.xxs),
        for (final reason in ReportReason.values)
          ReasonRadioRow(
            label: reason.label(context.l10n),
            isSelected: state.selectedReason == reason,
            onTap: () => viewModel.selectReason(reason),
          ),
        if (isOther) ...[
          const SizedBox(height: AppSpacing.xxs),
          _NoteBox(controller: _note, onChanged: viewModel.updateNote),
        ],
        if (state.error != null) ...[
          // pen 에 실패 상태가 없다 — 버튼 위에 빨간 한 줄로 둔다.
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.errorText(state.error!),
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
        // pen 은 사유 영역과 버튼 사이에 4px 투명 사각형(`CcGmL`)을 끼워 16 + 4 + 16 = 36 을 만든다.
        // 입력칸이 없을 때(pen 에 없는 상태)도 사유 영역 끝에서 같은 36 이다.
        const SizedBox(height: 36),
        SafetySheetButton.primary(
          label: context.l10n.commonReport,
          onPressed: state.canSubmit ? () => viewModel.submit(widget.target) : null,
        ),
        const SizedBox(height: AppSpacing.md),
        SafetySheetButton.neutral(label: context.l10n.commonCancel, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// 기타 메모(pen `UbMxg` = Textarea `Zhq9p`). 여러 줄 상자 320×104, 카운터는 상자 안 왼쪽 아래.
class _NoteBox extends StatelessWidget {
  const _NoteBox({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: reportNoteBoxKey,
      // 높이는 최소값만 — 여러 줄을 쓰거나 글자를 키우면 상자가 늘어난다.
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      // 테두리를 decoration 에 두면 Container 가 테두리 두께만큼 여백을 더한다 — pen 여백 12 는 바깥선 기준이다.
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            maxLines: null,
            // 200자는 코드포인트로 센다 — 서버 len() 이 그렇게 센다(입력 바와 같은 formatter). 줄 상한이 먼저다.
            inputFormatters: [
              lineBreakLimitFormatter(reportNoteMaxLines),
              codePointLimitFormatter(reportNoteMaxLength),
            ],
            style: AppTypography.bodySmall.copyWith(color: AppColors.ink, height: 1.5),
            decoration: InputDecoration.collapsed(
              hintText: context.l10n.safetyReportNoteHint,
              // pen `YgXMi` 14 / normal / muted / 1.5.
              hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 1.5),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => Text(
              '${value.text.runes.length} / $reportNoteMaxLength',
              // pen `BCwSP` 12 / normal / muted / 1.5.
              style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
