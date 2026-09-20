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
}
