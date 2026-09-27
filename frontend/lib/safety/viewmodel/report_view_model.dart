import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:campus_mate/safety/model/safety_errors.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시트 하나에 하나. 닫히면 버려져 다음 시트는 빈 선택에서 시작한다.
/// 대상은 [ReportViewModel.submit] 인자로 받는다 — 시트가 대상을 바꾸는 일이 없어 family 로 나눌 이유가 없다.
final reportViewModelProvider =
    NotifierProvider.autoDispose<ReportViewModel, ReportUiState>(ReportViewModel.new);

/// 신고 시트(계획서 A1). 서버가 차단을 먼저 하고 신고를 나중에 넣으므로(B1 ④ → ⑤),
/// **닫아도 되는 결과와 다시 보내야 하는 실패를 가르는 것**이 이 클래스의 일이다.
class ReportViewModel extends Notifier<ReportUiState> {
  @override
  ReportUiState build() => const ReportUiState();

  void selectReason(ReportReason reason) => state = state.copyWith(selectedReason: reason);

  void updateNote(String note) => state = state.copyWith(note: note);

  /// 실패 뒤에 다시 부르면 같은 요청을 그대로 보낸다. 서버 차단이 멱등이라 두 번 가도 안전하다.
  Future<void> submit(ReportTarget target) async {
    if (!state.canSubmit) return;
    state = state.copyWith(isSubmitting: true);
    final result = await ref.read(safetyRepositoryProvider).report(
          target: target,
          reason: state.selectedReason!,
          note: state.note,
        );
    // 응답을 기다리는 동안 시트를 밀어 닫으면 autoDispose 로 이미 버려졌다. 서버에는 이미 갔으니 여기서 끝낸다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) => state.copyWith(
        isSubmitting: false,
        outcome: ReportOutcome.reported,
        closingMessage: reportedMessage,
      ),
      onFailure: _failed,
    );
  }

  ReportUiState _failed(Failure failure) {
    final outcome = _closingOutcomeOf(failure);
    final message = reportFailureMessage(failure);
    if (outcome == null) return state.copyWith(isSubmitting: false, errorMessage: message);
    return state.copyWith(isSubmitting: false, outcome: outcome, closingMessage: message);
  }

  /// 다시 보내도 답이 같은 실패들. 나머지(네트워크 · 5xx 등)는 null — 시트를 열어 둔다.
  /// 닫아 버리면 "차단은 됐는데 신고는 안 된" 상태에서 진입점(방 · 14c)이 사라져 다시 신고할 길이 없다.
  ReportOutcome? _closingOutcomeOf(Failure failure) {
    if (isAlreadyReported(failure)) return ReportOutcome.alreadyReported;
    if (failure is RateLimitedFailure) return ReportOutcome.limited;
    if (isReportTargetGone(failure)) return ReportOutcome.targetGone;
    return null;
  }
}
