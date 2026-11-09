import 'package:campus_mate/billing/task/model/data/heart_task.dart';
import 'package:campus_mate/l10n/app_localizations.dart';

/// 운영자가 고르는 반려 사유(계획서 D3)의 글자. 18a 반려 줄 "반려 · …" 과 18b-2 "반려 사유: …" 뒤에 붙는다.
/// 서버 푸시 문구(`backend/app/admin/heart_task_notice.py` REASON_TEXT)도 같은 글자다.
extension HeartTaskRejectReasonText on HeartTaskRejectReason {
  String label(AppLocalizations l10n) => switch (this) {
        HeartTaskRejectReason.dateMissing => l10n.billingTaskRejectDateMissing,
        HeartTaskRejectReason.notVerified => l10n.billingTaskRejectNotVerified,
        HeartTaskRejectReason.reused => l10n.billingTaskRejectReused,
      };
}
