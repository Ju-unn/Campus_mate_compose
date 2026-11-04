import 'package:campus_mate/core/analytics/api_route_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

/// 오류 수집에 보내는 요청 경로에는 사람을 가리키는 값(id · 토큰 · 코드)이 들어가면 안 된다.
void main() {
  String patternOf(String url) => ApiRoutePattern.of(Uri.parse(url));

  test('값이 채워진 id(UUID)는 :id 로 바뀌고 쿼리 문자열은 떨어진다', () {
    expect(
      patternOf('https://api.test/cards/3f2a9c1e-7b4d-4e8a-9c21-5d6e7f8a9b0c/decision?x=1'),
      '/cards/:id/decision',
    );
  });

  test('앱이 부르는 고정 길 낱말(목록에 든 것)은 남긴다', () {
    expect(patternOf('https://api.test/profile-onboarding/next-step'), '/profile-onboarding/next-step');
    expect(patternOf('https://api.test/cards/today'), '/cards/today');
  });

  test('채팅방 id 가 가운데에 있어도 바뀐다', () {
    expect(
      patternOf('https://api.test/chat/matches/11111111-1111-4111-8111-111111111111/messages'),
      '/chat/matches/:id/messages',
    );
  });

  test('숫자 · 대문자 · 콜론이 든 조각(푸시 토큰 · 초대 코드)도 :id 다', () {
    expect(patternOf('https://api.test/cards/push-tokens/eXaMple:APA91bH-token_123'), '/cards/push-tokens/:id');
    expect(patternOf('https://api.test/reports/12345'), '/reports/:id');
    expect(patternOf('https://api.test/referral/ABCD'), '/referral/:id');
  });

  test('소문자 값(닉네임 · 영문 코드 · 토큰 조각)은 낱말 모양이어도 :id 다', () {
    expect(patternOf('https://api.test/profiles/minji'), '/profiles/:id');
    expect(patternOf('https://api.test/friend-reviews/targets/abcdef'), '/friend-reviews/targets/:id');
    expect(patternOf('https://api.test/cards/push-tokens/abcdeftoken'), '/cards/push-tokens/:id');
  });

  test('목록에 없는 낱말은 소문자 · 하이픈 모양이어도 :id 다', () {
    expect(patternOf('https://api.test/profiles/nickname/minji'), '/profiles/:id/:id');
    expect(patternOf('https://api.test/invites/abcdef'), '/:id/:id');
  });

  test('쿼리 문자열은 어떤 값이 있어도 결과에 없다', () {
    final pattern = patternOf('https://api.test/profile-onboarding/nickname-availability?nickname=%EC%97%AC%EC%9A%B0');
    expect(pattern, '/profile-onboarding/nickname-availability');
    expect(pattern, isNot(contains('?')));
  });

  test('조각이 6개를 넘으면 앞 6개만 본다', () {
    expect(
      patternOf('https://api.test/me/profile/me/profile/me/profile/me/profile'),
      '/me/profile/me/profile/me/profile',
    );
  });

  test('경로가 없으면 /', () {
    expect(patternOf('https://api.test'), '/');
    expect(patternOf('https://api.test/'), '/');
  });
}
