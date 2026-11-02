import 'package:campus_mate/core/analytics/api_route_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

/// 오류 수집에 보내는 요청 경로에는 사람을 가리키는 값(id · 토큰 · 코드)이 들어가면 안 된다.
void main() {
  String patternOf(String url) => ApiRoutePattern.of(Uri.parse(url));

  test('값이 채워진 id(UUID)는 :id 로 바뀌고 쿼리 문자열은 떨어진다', () {
    expect(
      patternOf('https://api.test/cards/3f2a9c1e-7b4d-4e8a-9c21-5d6e7f8a9b0c/accept?x=1'),
      '/cards/:id/accept',
    );
  });

  test('고정된 낱말(소문자 · 하이픈 · 밑줄)만 남긴다', () {
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

  test('낱말처럼 보여도 길이가 너무 길면 :id 다(정해진 길 이름은 짧다)', () {
    expect(patternOf('https://api.test/x/${'a' * 41}'), '/x/:id');
  });

  test('쿼리 문자열은 어떤 값이 있어도 결과에 없다', () {
    final pattern = patternOf('https://api.test/profile-onboarding/nickname-available?nickname=%EC%97%AC%EC%9A%B0');
    expect(pattern, '/profile-onboarding/nickname-available');
    expect(pattern, isNot(contains('?')));
  });

  test('조각이 6개를 넘으면 앞 6개만 본다', () {
    expect(patternOf('https://api.test/a/b/c/d/e/f/g/h'), '/a/b/c/d/e/f');
  });

  test('경로가 없으면 /', () {
    expect(patternOf('https://api.test'), '/');
    expect(patternOf('https://api.test/'), '/');
  });
}
