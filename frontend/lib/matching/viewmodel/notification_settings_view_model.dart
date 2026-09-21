import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationSettingsViewModelProvider =
    NotifierProvider<NotificationSettingsViewModel, NotificationSettingsUiState>(
  NotificationSettingsViewModel.new,
);

/// 알림 설정(화면 16d)과 매칭 일시중지(화면 16 `TLrmq`).
/// 스위치는 **먼저 화면에서 바꾸고 실패하면 되돌린다** — 토글은 즉시 반응해야 한다.
class NotificationSettingsViewModel extends Notifier<NotificationSettingsUiState> {
  Future<void>? _inFlight;

  @override
  NotificationSettingsUiState build() {
    Future.microtask(refresh);
    return const NotificationSettingsUiState();
  }

  Future<void> refresh() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    final result = await ref.read(cardRepositoryProvider).fetchNotificationPreferences();
    state = result.when(
      onSuccess: (preferences) => state.copyWith(isLoading: false, preferences: preferences),
      onFailure: (failure) =>
          state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  Future<void> toggle(String key, bool value) async {
    final previous = state.preferences;
    state = state.copyWith(preferences: previous.withValue(key, value), errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).updateNotificationPreference(key, value);
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) => state = state.copyWith(
        preferences: previous,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
  }

  Future<void> setPaused(bool paused) async {
    final previous = state.matchingPaused;
    state = state.copyWith(matchingPaused: paused, errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).setMatchingPaused(paused);
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) => state = state.copyWith(
        matchingPaused: previous,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
  }
}
