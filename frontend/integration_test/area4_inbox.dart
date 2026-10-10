import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
import 'package:campus_mate/notifications/view/notification_row.dart';
import 'package:campus_mate/notifications/view/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

/// 영역 4 알림함 E-INBOX-01 · 02(폰 한 대). PC 쪽은 e2e/area4_inbox.py 의 같은 번호 — 알림함 줄 셋(안 읽음)을 서버에 만들어 두고 이 앱을 켠다.
/// 앱은 홈 종 배지 → 알림함 → (01) 첫 줄 누르기 · (02) 모두 읽음 → 홈으로 돌아와 배지까지 본 것을 Map 으로 말하고 판정은 PC 가 한다.

const _inboxAppBarTitle = '알림'; // notifications_screen.dart 앱바
const _markAllRead = '모두 읽음'; // notifications_screen.dart 앱바 오른쪽 글자 버튼
const _receivedReviews = '받은 리뷰'; // 지인 리뷰 알림(route friend_reviews)이 여는 화면의 앱바 제목
const _badgeWait = Duration(seconds: 20); // 홈이 그려진 뒤 종 배지가 서버 값으로 맞춰지기를
const _screenWait = Duration(seconds: 15);

/// 앞 가설의 세션을 지우고 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area2_d.dart 와 같은 모양).
Area1Case _session(Area1Case body) => (tester, job) async {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

/// 종 배지의 안 읽은 수(종이 없으면 null).
int? _badge(WidgetTester tester) {
  final bell = find.byType(NotifyIconButton);
  return bell.evaluate().isEmpty ? null : tester.widget<NotifyIconButton>(bell.first).count;
}

/// 종 배지가 [want] 가 되기를 [within] 안에 기다린다. 끝내 안 되면 마지막으로 본 값.
Future<int?> _badgeBecomes(WidgetTester tester, int want, Duration within) async {
  final watch = Stopwatch()..start();
  while (_badge(tester) != want && watch.elapsed < within) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return _badge(tester);
}

/// 알림함에 그려진 줄들 — 줄마다 [제목, 본문]. 줄 안 글자는 제목 · 본문 · 시간 순이다.
List<List<String>> _rows(WidgetTester tester) {
  final rows = find.byType(NotificationRow);
  return [
    for (var i = 0; i < rows.evaluate().length; i++)
      [
        for (final text in find.descendant(of: rows.at(i), matching: find.byType(Text)).evaluate().take(2))
          (text.widget as Text).data ?? '',
      ],
  ];
}

/// 종을 눌러 알림함을 연다 — 줄이 그려질 때까지 기다린다.
Future<void> _openInbox(WidgetTester tester) async {
  await pumpUntil(tester, find.byType(NotifyIconButton), timeout: const Duration(seconds: 40));
  await tester.tap(find.byType(NotifyIconButton));
  await pumpUntil(tester, find.byType(NotificationRow), timeout: _screenWait);
}

/// 지금 맨 위 화면에서 한 겹 닫는다.
Future<void> _pop(WidgetTester tester, Finder onScreen) async {
  Navigator.of(tester.element(onScreen.first)).pop();
  await tester.pump(const Duration(milliseconds: 600));
}

final Map<String, Area1Case> area4InboxCases = {
  // 01: 홈 종 배지 → 알림함 줄 → 첫 줄 누르기(그 알림의 화면) → 돌아와 배지가 하나 줄었다.
  'E-INBOX-01': _session((tester, job) async {
    await pumpUntil(tester, find.byType(HomeScreen), timeout: const Duration(seconds: 40));
    final badge = await _badgeBecomes(tester, 3, _badgeWait);
    await _openInbox(tester);
    final rows = _rows(tester);
    await tester.tap(find.byType(NotificationRow).first);
    final reached = await appears(tester, find.text(_receivedReviews), _screenWait);
    final landed = reached == null ? null : _receivedReviews;
    if (reached != null) await _pop(tester, find.text(_receivedReviews)); // 알림함 위에 쌓여 있다 → 알림함
    await pumpUntil(tester, find.text(_inboxAppBarTitle), timeout: _screenWait);
    await _pop(tester, find.byType(NotificationsScreen)); // 알림함 → 홈
    await pumpUntil(tester, find.byType(NotifyIconButton), timeout: _screenWait);
    final after = await _badgeBecomes(tester, 2, _badgeWait);
    return {'badge': badge, 'rows': rows, 'landed': landed, 'badge_after': after};
  }),
  // 02: 알림함 "모두 읽음" → 버튼이 사라지고 줄은 그대로 → 돌아와 종 배지가 없다.
  'E-INBOX-02': _session((tester, job) async {
    await pumpUntil(tester, find.byType(HomeScreen), timeout: const Duration(seconds: 40));
    final badge = await _badgeBecomes(tester, 3, _badgeWait);
    await _openInbox(tester);
    await tester.tap(find.text(_markAllRead));
    var gone = false;
    final watch = Stopwatch()..start();
    while (!gone && watch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 200));
      gone = find.text(_markAllRead).evaluate().isEmpty;
    }
    final rowsAfter = find.byType(NotificationRow).evaluate().length;
    await _pop(tester, find.byType(NotificationsScreen));
    await pumpUntil(tester, find.byType(NotifyIconButton), timeout: _screenWait);
    final after = await _badgeBecomes(tester, 0, _badgeWait);
    return {'badge': badge, 'button_gone': gone, 'rows_after': rowsAfter, 'badge_after': after};
  }),
};
