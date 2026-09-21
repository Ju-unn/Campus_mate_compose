import 'package:campus_mate/core/push/push_route.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('카드 도착 알림은 오늘 탭으로 간다', () {
    expect(PushRoute.resolve({'route': 'daily_card', 'card_id': 'c1'}), AppRoutes.today);
  });

  test('받은 수락 알림은 대화 목록으로 간다', () {
    expect(PushRoute.resolve({'route': 'acceptances', 'card_id': 'c1'}), AppRoutes.conversations);
  });

  test('매칭 성사 알림도 대화 목록으로 간다 — 채팅방은 조각 5다', () {
    expect(PushRoute.resolve({'route': 'match', 'match_id': 'm1'}), AppRoutes.conversations);
  });

  test('모르는 route 는 아무 데도 보내지 않는다', () {
    expect(PushRoute.resolve({'route': 'new_message'}), isNull);
    expect(PushRoute.resolve(const {}), isNull);
  });
}
