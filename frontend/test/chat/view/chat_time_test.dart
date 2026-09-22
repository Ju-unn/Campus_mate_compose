import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('오전·오후와 12시를 제대로 읽는다', () {
    expect(timeLabel(DateTime(2026, 9, 22, 14, 14)), '오후 2:14');
    expect(timeLabel(DateTime(2026, 9, 22, 9, 5)), '오전 9:05');
    expect(timeLabel(DateTime(2026, 9, 22, 12, 0)), '오후 12:00');
    expect(timeLabel(DateTime(2026, 9, 22, 0, 30)), '오전 12:30');
  });

  test('날짜 구분선은 요일까지 적는다', () {
    expect(dateLabel(DateTime(2026, 9, 14)), '9월 14일 월요일');
  });

  test('목록은 오늘이면 시각, 아니면 날짜를 보여준다', () {
    final now = DateTime(2026, 9, 22, 15, 0);
    expect(listTimeLabel(DateTime(2026, 9, 22, 14, 14), now), '오후 2:14');
    // 사흘 전 대화에 시계만 떠 있으면 언제 이야기했는지 알 수 없다.
    expect(listTimeLabel(DateTime(2026, 9, 19, 14, 14), now), '9월 19일');
  });

  test('카운트다운은 하루가 넘어도 시 자리에 쌓는다', () {
    expect(countdownLabel(const Duration(hours: 21, minutes: 34, seconds: 10)), '21:34:10');
    expect(countdownLabel(const Duration(hours: 47, minutes: 0, seconds: 5)), '47:00:05');
    // 기한이 지나도 음수를 보여주지 않는다.
    expect(countdownLabel(const Duration(seconds: -5)), '00:00:00');
  });
}
