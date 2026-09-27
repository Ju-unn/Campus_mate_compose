import 'package:campus_mate/safety/model/report_reason.dart';

/// 성공 뒤 안내(계획서 A1). 신고하면 차단도 같이 된다는 것(결정 4)을 숨기지 않고 알린다.
const String reportedMessage = '신고했어요. 이 사용자는 차단되어 서로에게 보이지 않아요.';

/// 시트를 **닫아야 하는** 결과들. 여기에 없는 실패는 시트를 열어 둔 채 다시 보내게 한다.
enum ReportOutcome {
  /// 신고 + 차단 완료.
  reported,

  /// 409. 첫 요청이 사실 성공했을 수 있어 끝난 것으로 친다 — 이때도 차단은 돼 있다.
  alreadyReported,

  /// 429 하루 상한. 서버가 차단 전에 막으므로 **차단은 안 됐다**.
  limited,

  /// 404 프로필 · 메시지가 사라졌다. 다시 보내도 같은 답이다.
  targetGone,
}

/// 신고 시트 하나의 상태.
class ReportUiState {
  const ReportUiState({
    this.selectedReason,
    this.note = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.outcome,
    this.closingMessage,
  });

  final ReportReason? selectedReason;

  /// 기타 메모 원문. 200자 자르기는 화면 입력기 몫이고 여기서는 다듬어 비었는지만 본다.
  final String note;
  final bool isSubmitting;

  /// 시트를 열어 둔 채 띄우는 실패 문구("다시 시도").
  final String? errorMessage;

  /// null 이 아니면 시트를 닫고 [closingMessage] 를 띄운다.
  final ReportOutcome? outcome;
  final String? closingMessage;

  /// 사유를 골랐고, 보내는 중이 아니고, 아직 끝나지 않았고, 기타라면 메모가 있을 때.
  bool get canSubmit =>
      selectedReason != null &&
      !isSubmitting &&
      outcome == null &&
      (selectedReason != ReportReason.other || note.trim().isNotEmpty);

  /// [errorMessage] 는 넘기지 않으면 지워진다 — 다음 동작을 하면 지난 실패 문구가 사라져야 한다.
  ReportUiState copyWith({
    ReportReason? selectedReason,
    String? note,
    bool? isSubmitting,
    String? errorMessage,
    ReportOutcome? outcome,
    String? closingMessage,
  }) {
    return ReportUiState(
      selectedReason: selectedReason ?? this.selectedReason,
      note: note ?? this.note,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      outcome: outcome ?? this.outcome,
      closingMessage: closingMessage ?? this.closingMessage,
    );
  }
}
