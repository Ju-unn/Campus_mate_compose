import 'package:campus_mate/core/analytics/screen_view_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_analytics_service.dart';

Route<void> _route(String? name) =>
    MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: (_) => const SizedBox());

void main() {
  late FakeAnalyticsService analytics;
  late ScreenViewObserver observer;

  setUp(() {
    analytics = FakeAnalyticsService();
    observer = ScreenViewObserver(analytics);
  });

  test('화면이 쌓이면 그 경로 이름을 기록한다', () {
    observer.didPush(_route('/home'), null);

    expect(analytics.calls, ['screen:/home']);
  });

  test('이름이 없는 길(바닥 시트 · 대화상자)은 기록하지 않는다', () {
    observer.didPush(_route(null), _route('/home'));

    expect(analytics.calls, isEmpty);
  });

  test('화면이 걷히고 앞 화면이 다시 보이면 앞 화면을 기록한다', () {
    observer.didPop(_route('/chat/:matchId'), _route('/conversations'));

    expect(analytics.calls, ['screen:/conversations']);
  });

  // 바닥 시트 · 대화상자(이름 없는 길)가 닫혀도 아래 화면은 계속 보이던 것이라 새 화면 조회가 아니다.
  test('이름 없는 길(바닥 시트 · 대화상자)이 닫힐 때는 아래 화면을 다시 기록하지 않는다', () {
    observer.didPop(_route(null), _route('/home'));

    expect(analytics.calls, isEmpty);
  });

  test('바닥이 걷혀 앞 화면이 없으면 기록하지 않는다', () {
    observer.didPop(_route('/home'), null);

    expect(analytics.calls, isEmpty);
  });

  test('화면이 바뀌어 들어가면(replace) 새 화면을 기록한다', () {
    observer.didReplace(newRoute: _route('/today'), oldRoute: _route('/home'));

    expect(analytics.calls, ['screen:/today']);
  });

  // 경로 변수에 든 id(채팅방 · 카드 · 상대 프로필)가 이름에 섞이면 사람을 가리키는 값이 된다 — 이름은 패턴 그대로다.
  test('경로 변수 자리는 값이 아니라 패턴 이름 그대로 기록한다', () {
    observer.didPush(_route('/chat/:matchId'), null);

    expect(analytics.calls.single, isNot(contains('-')));
    expect(analytics.calls, ['screen:/chat/:matchId']);
  });
}
