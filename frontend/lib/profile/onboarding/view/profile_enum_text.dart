import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';

/// 동물상 · 인상 · 종교 · 유입경로 칩의 화면 글자(문구 파일 ARB). enum 은 서버 값만 들고, 글자는 view 쪽이 정한다.
/// 04-4(본인) · 06-1(선호) · 15-6(기본 정보 수정) · 카드 상세가 같은 글자를 쓴다(DESIGN.md §8.5).
extension AnimalTypeText on AnimalType {
  String label(AppLocalizations l10n) => switch (this) {
        AnimalType.dog => l10n.profileAnimalTypeDog,
        AnimalType.cat => l10n.profileAnimalTypeCat,
        AnimalType.fox => l10n.profileAnimalTypeFox,
        AnimalType.bear => l10n.profileAnimalTypeBear,
        AnimalType.rabbit => l10n.profileAnimalTypeRabbit,
        AnimalType.deer => l10n.profileAnimalTypeDeer,
        AnimalType.wolf => l10n.profileAnimalTypeWolf,
        AnimalType.hamster => l10n.profileAnimalTypeHamster,
      };
}

extension ImpressionTypeText on ImpressionType {
  String label(AppLocalizations l10n) => switch (this) {
        ImpressionType.arab => l10n.profileImpressionTypeArab,
        ImpressionType.tofu => l10n.profileImpressionTypeTofu,
        ImpressionType.kind => l10n.profileImpressionTypeKind,
        ImpressionType.chic => l10n.profileImpressionTypeChic,
        ImpressionType.innocent => l10n.profileImpressionTypeInnocent,
      };
}

extension ReligionText on Religion {
  String label(AppLocalizations l10n) => switch (this) {
        Religion.none => l10n.profileReligionNone,
        Religion.protestant => l10n.profileReligionProtestant,
        Religion.catholic => l10n.profileReligionCatholic,
        Religion.buddhist => l10n.profileReligionBuddhist,
      };
}

/// 20d 유입경로 칩 글자. 서버로 가는 값은 글자가 아니라 `name` 이다.
extension AcquisitionChannelText on AcquisitionChannel {
  String label(AppLocalizations l10n) => switch (this) {
        AcquisitionChannel.everytime => l10n.profileAcquisitionChannelEverytime,
        AcquisitionChannel.instagram => l10n.profileAcquisitionChannelInstagram,
        AcquisitionChannel.friend => l10n.profileAcquisitionChannelFriend,
        AcquisitionChannel.community => l10n.profileAcquisitionChannelCommunity,
        AcquisitionChannel.other => l10n.profileAcquisitionChannelOther,
      };
}
