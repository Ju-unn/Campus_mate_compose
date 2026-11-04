import 'package:campus_mate/consent/model/data/consent_item.dart';
import 'package:campus_mate/l10n/app_localizations.dart';

/// 약관 동의 줄의 글자(pen 02-c, 문구 파일 ARB). enum 은 식별자만 들고, 글자는 view 쪽이 정한다.
extension ConsentItemText on ConsentItem {
  String label(AppLocalizations l10n) => switch (this) {
        ConsentItem.terms => l10n.consentItemTerms,
        ConsentItem.privacy => l10n.consentItemPrivacy,
        ConsentItem.marketing => l10n.consentItemMarketing,
      };
}
