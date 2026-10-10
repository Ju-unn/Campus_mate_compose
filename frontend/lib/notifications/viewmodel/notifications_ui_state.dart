import 'package:campus_mate/notifications/model/app_notification.dart';

/// 알림함 화면의 네 모습(pen 09c: 목록 `WiGM2` · 빈 상태 `fANzR` · 불러오기 실패 `vGd3l` · 로딩 `QUfcS`).
enum NotificationsPhase { loading, list, empty, failed }

class NotificationsUiState {
  const NotificationsUiState({
    this.phase = NotificationsPhase.loading,
    this.items = const [],
    this.nextBefore,
    this.isLoadingMore = false,
  });

  final NotificationsPhase phase;
  final List<AppNotification> items;

  /// null 이면 더 읽을 쪽이 없다.
  final String? nextBefore;
  final bool isLoadingMore;

  NotificationsUiState copyWith({
    NotificationsPhase? phase,
    List<AppNotification>? items,
    String? nextBefore,
    bool clearNextBefore = false,
    bool? isLoadingMore,
  }) =>
      NotificationsUiState(
        phase: phase ?? this.phase,
        items: items ?? this.items,
        nextBefore: clearNextBefore ? null : (nextBefore ?? this.nextBefore),
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}
