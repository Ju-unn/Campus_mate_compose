import 'package:campus_mate/graduate/model/data/graduate_request_state.dart';
import 'package:campus_mate/l10n/app_localizations.dart';

/// 반려 알림 첫 줄에 붙는 사유 글자(문구 파일 ARB). 대장 확정 D10(10-19): 앱 · 푸시 · 관리자 웹이 같은 글자 네 개를 쓴다.
/// 앞 셋은 값표 §5 사유 예시 3개(pen 02-g-3), 넷째 `school_unsupported` 는 시안에 없어 같은 틀로 추가했다(값표에 없어 임의).
/// 서버 푸시 문구(`backend/app/admin/graduate_notice.py` REASON_TEXT)도 같은 글자다(대장이 맞췄다).
extension GraduateRejectReasonText on GraduateRejectReason {
  String label(AppLocalizations l10n) => switch (this) {
        GraduateRejectReason.unreadable => l10n.graduateRejectReasonUnreadable,
        GraduateRejectReason.notCertificate => l10n.graduateRejectReasonNotCertificate,
        GraduateRejectReason.unverifiable => l10n.graduateRejectReasonUnverifiable,
        GraduateRejectReason.schoolUnsupported => l10n.graduateRejectReasonSchoolUnsupported,
      };
}
