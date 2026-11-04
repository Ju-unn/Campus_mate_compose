import 'package:campus_mate/faq/model/data/faq_item.dart';
import 'package:campus_mate/l10n/app_localizations.dart';

/// FAQ 묶음의 탭 · 묶음 제목 글자(문구 파일 ARB). enum 은 식별자만 들고, 글자는 view 쪽이 정한다.
extension FaqCategoryText on FaqCategory {
  String label(AppLocalizations l10n) => switch (this) {
        FaqCategory.cardMatching => l10n.faqCategoryCardMatching,
        FaqCategory.heartPayment => l10n.faqCategoryHeartPayment,
        FaqCategory.photoProfile => l10n.faqCategoryPhotoProfile,
        FaqCategory.friendReview => l10n.faqCategoryFriendReview,
        FaqCategory.safety => l10n.faqCategorySafety,
        FaqCategory.account => l10n.faqCategoryAccount,
      };
}
