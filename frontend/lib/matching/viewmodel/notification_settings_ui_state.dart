import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/data/notification_preferences.dart';

/// 알림 설정(16d)과 매칭 일시중지(16 `TLrmq`)의 상태.
/// [error] 는 [copyWith] 에서 덮어쓰기다 — 다음 동작이 시작되면 지워져야 한다.
class NotificationSettingsUiState {
  const NotificationSettingsUiState({
    this.isLoading = true,
    this.preferences = const NotificationPreferences(),
    this.matchingPaused = false,
    this.error,
  });

  final bool isLoading;
  final NotificationPreferences preferences;

  /// 화면 16 의 "매칭 활성화" 는 이 값의 반대다(꺼짐 = 일시중지).
  final bool matchingPaused;
  final Failure? error;

  NotificationSettingsUiState copyWith({
    bool? isLoading,
    NotificationPreferences? preferences,
    bool? matchingPaused,
    Failure? error,
  }) {
    return NotificationSettingsUiState(
      isLoading: isLoading ?? this.isLoading,
      preferences: preferences ?? this.preferences,
      matchingPaused: matchingPaused ?? this.matchingPaused,
      error: error,
    );
  }
}
