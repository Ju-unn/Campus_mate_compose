import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/safety/model/data/report_reason.dart';

/// 신고 시트 라디오에 보이는 사유 글자(pen `yl8gX` — xarhn · AMxAh · w8qR7 · BHphm · YhPFL). enum 은 서버 값만 들고, 글자는 view 쪽이 정한다.
extension ReportReasonText on ReportReason {
  String label(AppLocalizations l10n) => switch (this) {
        ReportReason.abuse => l10n.safetyReportReasonAbuse,
        ReportReason.sexual => l10n.safetyReportReasonSexual,
        ReportReason.spam => l10n.safetyReportReasonSpam,
        ReportReason.fake => l10n.safetyReportReasonFake,
        ReportReason.other => l10n.safetyReportReasonOther,
      };
}
