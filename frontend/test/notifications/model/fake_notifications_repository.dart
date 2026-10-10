import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/notifications/model/app_notification.dart';
import 'package:campus_mate/notifications/model/notifications_repository.dart';

AppNotification fakeNotification(
  String id, {
  NotificationKind kind = NotificationKind.cardArrived,
  String? title,
  String body = '지금 확인해 보세요',
  Map<String, dynamic> data = const {'route': 'friend_reviews'},
  DateTime? createdAt,
  bool read = false,
}) =>
    AppNotification(
      id: id,
      kind: kind,
      title: title ?? '알림 $id',
      body: body,
      data: data,
      createdAt: createdAt ?? DateTime(2026, 10, 10, 9),
      read: read,
    );

/// 테스트가 돌려줄 값을 직접 정하는 가짜 저장소. 쪽은 [pages] 를 차례로 내준다(첫 쪽 → 둘째 쪽 …).
class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository({List<NotificationsPage>? pages, this.unreadCount = 0})
      : pages = pages ?? [const NotificationsPage(items: [], unreadCount: 0)];

  List<NotificationsPage> pages;
  int unreadCount;

  /// true 면 그 읽기들이 실패한다.
  bool failList = false;
  bool failCount = false;
  bool failRead = false;

  /// 채우면 그 호출이 이 Completer 가 끝날 때까지 기다린다.
  Completer<void>? holdList;
  Completer<void>? holdRead;
  Completer<void>? holdCount;

  final List<String?> listBefores = [];
  final List<String> markedRead = [];
  int readAllCount = 0;
  int countCalls = 0;

  @override
  Future<Result<NotificationsPage>> fetchPage({int limit = 30, String? before}) async {
    listBefores.add(before);
    await holdList?.future;
    if (failList) return const FailureResult(NetworkFailure());
    final index = before == null ? 0 : listBefores.where((b) => b != null).length;
    return Success(pages[index.clamp(0, pages.length - 1)]);
  }

  @override
  Future<Result<int>> fetchUnreadCount() async {
    countCalls++;
    await holdCount?.future;
    if (failCount) return const FailureResult(NetworkFailure());
    return Success(unreadCount);
  }

  @override
  Future<Result<void>> markRead(String id) async {
    await holdRead?.future;
    if (failRead) return const FailureResult(NetworkFailure());
    markedRead.add(id);
    if (unreadCount > 0) unreadCount--;
    return const Success(null);
  }

  @override
  Future<Result<void>> markAllRead() async {
    await holdRead?.future;
    if (failRead) return const FailureResult(NetworkFailure());
    readAllCount++;
    unreadCount = 0;
    return const Success(null);
  }
}
