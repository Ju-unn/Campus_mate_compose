import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// 외모 타입 화면(DESIGN.md 화면 04-4)의 상태.
class AppearanceTypeUiState {
  const AppearanceTypeUiState({
    this.animalType,
    this.impressionType,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final AnimalType? animalType;
  final ImpressionType? impressionType;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  bool get canSubmit => animalType != null && impressionType != null && !isSubmitting;

  /// 폰에 임시 저장할 값 — 고른 두 가지뿐이다.
  Map<String, Object?> toDraft() => {'animalType': animalType?.name, 'impressionType': impressionType?.name};

  /// 뒤로가기로 돌아왔을 때 서버에 저장해 둔 얼굴상 · 인상으로 처음 상태를 만든다.
  static AppearanceTypeUiState fromProfile(MyProfile profile) {
    return AppearanceTypeUiState(animalType: profile.animalType, impressionType: profile.impressionType);
  }

  /// [toDraft] 로 남긴 값으로 처음 상태를 만든다. 모르는 이름이면(`byName`) 던진다 — 저장소가 받아서 버린다.
  static AppearanceTypeUiState fromDraft(Map<String, Object?> data) {
    final animal = data['animalType'] as String?;
    final impression = data['impressionType'] as String?;
    return AppearanceTypeUiState(
      animalType: animal == null ? null : AnimalType.values.byName(animal),
      impressionType: impression == null ? null : ImpressionType.values.byName(impression),
    );
  }
}
