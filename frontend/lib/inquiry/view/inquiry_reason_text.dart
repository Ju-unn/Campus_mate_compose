import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/l10n/app_localizations.dart';

/// 문의 사유 칸 · 시트 라디오에 보이는 글자(pen 21b `Ywu44` — zEIEr · s5azT1 · d8rBt · tYsNG · azPoP · i1R84).
/// enum 은 서버 값만 들고, 글자는 view 쪽이 정한다 — 서버 문구("계정·인증")는 운영자가 보는 말이라 띄어쓰기가 다르다.
extension InquiryReasonText on InquiryReason {
  String label(AppLocalizations l10n) => switch (this) {
        InquiryReason.account => l10n.inquiryReasonAccount,
        InquiryReason.payment => l10n.inquiryReasonPayment,
        InquiryReason.matching => l10n.inquiryReasonMatching,
        InquiryReason.safety => l10n.inquiryReasonSafety,
        InquiryReason.bug => l10n.inquiryReasonBug,
        InquiryReason.other => l10n.inquiryReasonOther,
      };
}
