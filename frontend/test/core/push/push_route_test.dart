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

  test('매칭 성사 알림은 대화 목록으로 간다 — 방은 목록에서 골라 들어간다', () {
    expect(PushRoute.resolve({'route': 'match', 'match_id': 'm1'}), AppRoutes.conversations);
  });

  test('채팅 알림은 그 방으로 바로 간다', () {
    expect(PushRoute.resolve({'route': 'chat', 'match_id': 'm1'}), '/chat/m1');
  });

  test('방 id 가 없는 채팅 알림은 목록으로 보낸다', () {
    // 엉뚱한 방을 여는 것보다 목록이 낫다.
    expect(PushRoute.resolve({'route': 'chat'}), AppRoutes.conversations);
    expect(PushRoute.resolve({'route': 'chat', 'match_id': ''}), AppRoutes.conversations);
  });

  test('새 지인 리뷰 알림은 받은 리뷰(20c)로 간다', () {
    expect(PushRoute.resolve({'route': 'friend_reviews'}), AppRoutes.friendReviews);
  });

  test('추천 가입 알림은 홈 위에 그 친구의 리뷰 쓰기(20b)를 연다', () {
    expect(PushRoute.resolve({'route': 'friend_review_write', 'profile_id': 'p2'}), '/home/friend-reviews/write/p2');
  });

  test('누구에게 쓸지 모르는 리뷰 쓰기 알림은 아무 데도 보내지 않는다', () {
    expect(PushRoute.resolve({'route': 'friend_review_write'}), isNull);
    expect(PushRoute.resolve({'route': 'friend_review_write', 'profile_id': ''}), isNull);
  });

  test('모르는 route 는 아무 데도 보내지 않는다', () {
    expect(PushRoute.resolve({'route': 'sticker'}), isNull);
    expect(PushRoute.resolve(const {}), isNull);
  });
}
