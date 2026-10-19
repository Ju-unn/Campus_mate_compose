import 'package:campus_mate/matching/model/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026-10-19 사용자: 처음에는 방해 금지 시간(22~08시)을 꺼 둔다 — 서버 기본값(NOTIFICATION_DEFAULTS)과 같은 값.
  test('처음 받는 알림 설정은 방해 금지 시간이 꺼져 있다', () {
    expect(const NotificationPreferences().quietHours, isFalse);
    expect(NotificationPreferences.fromJson(const {}).quietHours, isFalse);
  });

  test('서버가 보낸 방해 금지 시간 값은 그대로 읽는다 — 이미 켠 사람은 켜진 채다', () {
    expect(NotificationPreferences.fromJson(const {'quiet_hours': true}).quietHours, isTrue);
    expect(NotificationPreferences.fromJson(const {'quiet_hours': false}).quietHours, isFalse);
  });

  test('나머지 스위치의 기본값은 그대로다(마케팅만 꺼짐)', () {
    const defaults = NotificationPreferences();
    expect([defaults.cardArrived, defaults.acceptanceReceived, defaults.matchMade, defaults.newMessage, defaults.trustReminder, defaults.newFriendReview],
        everyElement(isTrue));
    expect(defaults.marketing, isFalse);
  });
}
