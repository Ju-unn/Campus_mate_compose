import 'package:campus_mate/core/router/splash_hold.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 2초를 기다리면 테스트가 느려지므로 짧은 시간을 넣어 규칙만 본다.
const _shortHold = Duration(milliseconds: 20);

void main() {
  test('만들자마자는 스플래시를 붙잡는다', () {
    final hold = SplashHold(duration: _shortHold);
    addTearDown(hold.dispose);

    expect(hold.isHolding(), isTrue);
  });

  test('시간이 지나면 놓아주고 한 번 알린다', () async {
    final hold = SplashHold(duration: _shortHold);
    addTearDown(hold.dispose);
    var notifiedCount = 0;
    hold.addListener(() => notifiedCount += 1);

    await Future<void>.delayed(_shortHold * 3);

    expect(hold.isHolding(), isFalse);
    expect(notifiedCount, 1);
  });

  test('시간이 되기 전에 버리면 알리지 않는다', () async {
    final hold = SplashHold(duration: _shortHold);
    var notifiedCount = 0;
    hold.addListener(() => notifiedCount += 1);

    hold.dispose();
    await Future<void>.delayed(_shortHold * 3);

    expect(notifiedCount, 0);
  });
}
