import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 홈 종 배지의 "안 읽은 알림 수". 홈이 들어올 때 · 앱이 돌아올 때 · 알림함에서 돌아올 때 [refresh] 로 서버 값을 읽고,
/// 알림함 안에서는 읽을 때마다 뷰모델이 바로 맞춘다(낙관적 갱신).
final unreadCountProvider = NotifierProvider<UnreadCountNotifier, int>(UnreadCountNotifier.new);

class UnreadCountNotifier extends Notifier<int> {
  /// 아직 서버에 닿지 않은 읽음 요청들. 알림을 누르자마자 홈으로 가면 수를 읽는 요청이 읽음 요청보다
  /// 먼저 닿아 배지가 되살아날 수 있어, [refresh] 는 이 요청들이 끝난 뒤에 읽는다.
  final Set<Future<void>> _pending = {};

  @override
  int build() => 0;

  /// 서버 값으로 맞춘다. 못 읽으면 앞의 값을 그대로 둔다(배지가 잠깐 틀려도 화면을 막지 않는다).
  Future<void> refresh() async {
    if (_pending.isNotEmpty) await Future.wait(_pending.toList());
    final result = await ref.read(notificationsRepositoryProvider).fetchUnreadCount();
    if (!ref.mounted) return;
    result.when(onSuccess: (count) => state = count, onFailure: (_) {});
  }

  void set(int count) => state = count < 0 ? 0 : count;

  void decrement() => state = state > 0 ? state - 1 : 0;

  /// 읽음 요청 하나를 등록한다 — 끝나면 저절로 빠진다.
  void track(Future<void> request) {
    _pending.add(request);
    request.whenComplete(() => _pending.remove(request));
  }
}
