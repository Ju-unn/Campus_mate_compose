import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/profile/traits/viewmodel/tag_picker_kind.dart';

/// 관심사(04-5) · 나의 특징(04-6) · 이상형 특징(06-2) 화면의 글자(문구 파일 ARB). 15c 자기소개 · 태그 수정의 섹션 라벨도
/// 같은 태그 이름을 쓴다.
extension TagPickerKindText on TagPickerKind {
  String headline(AppLocalizations l10n) => switch (this) {
        TagPickerKind.interests => l10n.profileTagInterestsHeadline,
        TagPickerKind.myTraits => l10n.profileTagMyTraitsHeadline,
        TagPickerKind.idealTraits => l10n.profileTagIdealTraitsHeadline,
      };

  String subtext(AppLocalizations l10n) => switch (this) {
        TagPickerKind.interests => l10n.profileTagInterestsSubtext,
        TagPickerKind.myTraits => l10n.profileTagMyTraitsSubtext,
        TagPickerKind.idealTraits => l10n.profileTagIdealTraitsSubtext,
      };

  String tagName(AppLocalizations l10n) => switch (this) {
        TagPickerKind.interests => l10n.profileTagInterestsName,
        TagPickerKind.myTraits => l10n.profileTagMyTraitsName,
        TagPickerKind.idealTraits => l10n.profileTagIdealTraitsName,
      };

  /// 태그 칸 라벨 — 이름 뒤에 [TagPickerKind.minCount] · [TagPickerKind.maxCount] 를 붙인다.
  String tagLabel(AppLocalizations l10n) =>
      l10n.profileTagCountLabel(name: tagName(l10n), min: TagPickerKind.minCount, max: TagPickerKind.maxCount);
}
