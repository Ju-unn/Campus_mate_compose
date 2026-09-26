import 'package:campus_mate/community/view/poll_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 27, 14);

  test('상대 시간', () {
    expect(relativeTimeLabel(now.subtract(const Duration(seconds: 30)), now), '방금 전');
    expect(relativeTimeLabel(now.subtract(const Duration(minutes: 5)), now), '5분 전');
    expect(relativeTimeLabel(now.subtract(const Duration(hours: 3)), now), '3시간 전');
    // pen 카드 `e45gI1` 의 시각이 "어제" 다 — 하루 전은 "1일 전" 이 아니라 "어제".
    expect(relativeTimeLabel(now.subtract(const Duration(hours: 30)), now), '어제');
    expect(relativeTimeLabel(now.subtract(const Duration(days: 2)), now), '2일 전');
    expect(relativeTimeLabel(DateTime(2026, 9, 1), now), '9월 1일');
  });

  test('기기 시계가 서버보다 느려 미래 시각이 와도 방금 전', () {
    expect(relativeTimeLabel(now.add(const Duration(minutes: 1)), now), '방금 전');
  });
}
