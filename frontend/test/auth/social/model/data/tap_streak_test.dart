import 'package:campus_mate/auth/social/model/data/tap_streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 11, 4, 12);

  /// [count] 번을 [gap] 간격으로 누른다. 마지막 탭의 결과를 돌려준다.
  bool tapTimes(TapStreak streak, int count, {Duration gap = const Duration(milliseconds: 300), DateTime? from}) {
    var now = from ?? start;
    var opened = false;
    for (var i = 0; i < count; i++) {
      opened = streak.register(now);
      now = now.add(gap);
    }
    return opened;
  }

  test('일곱 번째 탭에서 처음으로 true 가 된다 — 여섯 번까지는 false', () {
    final streak = TapStreak();

    final results = [for (var i = 0; i < TapStreak.taps; i++) streak.register(start.add(Duration(milliseconds: 200 * i)))];

    expect(TapStreak.taps, 7);
    expect(results, [false, false, false, false, false, false, true]);
  });

  test('여섯 번만 누르면 열리지 않는다', () {
    expect(tapTimes(TapStreak(), 6), isFalse);
  });

  test('한도(5초) 안에 일곱 번이면 열린다 — 첫 탭과 일곱 번째 탭 사이가 정확히 5초여도 된다', () {
    final streak = TapStreak();
    // 0 s 에 한 번, 사이를 비우고 5 s 에 여섯 번 — 첫 탭과 일곱 번째 탭 사이가 한도와 같다.
    streak.register(start);

    expect(tapTimes(streak, 6, gap: Duration.zero, from: start.add(TapStreak.window)), isTrue);
  });

  test('첫 탭에서 한도를 넘기면 그 탭은 세지 않는다 — 일곱 번째가 한도 밖이면 false', () {
    final streak = TapStreak();
    streak.register(start);

    expect(tapTimes(streak, 6, gap: Duration.zero, from: start.add(TapStreak.window + const Duration(milliseconds: 1))), isFalse);
  });

  test('여섯 번 누르고 한도를 넘겨 쉬면 처음부터 다시 센다 — 이어서 한 번 더 눌러도 열리지 않는다', () {
    final streak = TapStreak();
    tapTimes(streak, 6);

    final afterPause = start.add(const Duration(seconds: 10));

    expect(streak.register(afterPause), isFalse);
  });

  test('쉰 뒤에는 새로 일곱 번을 눌러야 열린다', () {
    final streak = TapStreak();
    tapTimes(streak, 6);
    final afterPause = start.add(const Duration(seconds: 10));

    expect(tapTimes(streak, 6, from: afterPause), isFalse, reason: '쉰 뒤 첫 탭부터 여섯 번이라 아직 6');
    expect(streak.register(afterPause.add(const Duration(seconds: 2))), isTrue);
  });

  test('열린 뒤에는 처음부터 다시 센다 — 바로 이어 눌러도 일곱 번을 새로 채워야 한다', () {
    final streak = TapStreak();
    tapTimes(streak, 7);

    final after = start.add(const Duration(seconds: 3));

    expect(tapTimes(streak, 6, from: after), isFalse);
    expect(streak.register(after.add(const Duration(seconds: 2))), isTrue);
  });

  test('열린 뒤 일곱 번을 새로 채우면 다시 열린다', () {
    final streak = TapStreak();
    tapTimes(streak, 7);

    expect(tapTimes(streak, 7, from: start.add(const Duration(seconds: 2))), isTrue);
  });

  test('한도 안이면 탭 사이가 길어도 센다 — 1.5초 간격 일곱 번(9초)은 열리지 않고, 0.6초 간격은 열린다', () {
    expect(tapTimes(TapStreak(), 7, gap: const Duration(milliseconds: 1500)), isFalse);
    expect(tapTimes(TapStreak(), 7, gap: const Duration(milliseconds: 600)), isTrue);
  });
}
