import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:flutter/widgets.dart';
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

  test('큰 단위 표기는 한 시간이 안 남으면 분으로 내려간다', () {
    expect(coarseRemainingLabel(const Duration(hours: 3, minutes: 20)), '3시간');
    expect(coarseRemainingLabel(const Duration(hours: 1)), '1시간');
    // "0시간 뒤 종료돼요" 가 뜨면 안 된다.
    expect(coarseRemainingLabel(const Duration(minutes: 40)), '40분');
    expect(coarseRemainingLabel(const Duration(seconds: 20)), '1분');
  });

  // 기한이 0 이 되면 한 번만 알린다 — 홈 hero ③ · 오늘 탭 11 이 다음 카드를 다시 읽는 신호다.
  // 남은 시간은 기기 시계(DateTime.now)로 세서, 실제 시간을 흘린 뒤(runAsync) 타이머를 돌린다.
  group('CountdownBuilder.onDone', () {
    Future<void> pump(WidgetTester tester, DateTime deadline, VoidCallback onDone) => tester.pumpWidget(
          CountdownBuilder(
            deadlineAt: deadline,
            onDone: onDone,
            builder: (context, remaining) => Text(countdownLabel(remaining), textDirection: TextDirection.ltr),
          ),
        );

    /// 실제 시계를 [real] 만큼 흘리고 1초 타이머를 [ticks] 번 돌린다.
    Future<void> elapse(WidgetTester tester, Duration real, {int ticks = 1}) async {
      await tester.runAsync(() => Future<void>.delayed(real));
      for (var i = 0; i < ticks; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    }

    testWidgets('0 이 되면 한 번 부르고, 그 뒤로 1초가 더 흘러도 다시 부르지 않는다', (tester) async {
      var calls = 0;
      await pump(tester, DateTime.now().add(const Duration(milliseconds: 300)), () => calls++);
      expect(calls, 0);

      await elapse(tester, const Duration(milliseconds: 500));
      expect(calls, 1);
      await elapse(tester, const Duration(milliseconds: 10), ticks: 3);
      expect(calls, 1);
    });

    testWidgets('이미 지난 시각으로 시작해도 한 번만 부른다', (tester) async {
      var calls = 0;
      await pump(tester, DateTime.now().subtract(const Duration(minutes: 1)), () => calls++);
      await tester.pump();
      expect(calls, 1);

      await elapse(tester, const Duration(milliseconds: 10), ticks: 3);
      expect(calls, 1);
    });

    testWidgets('같은 기한으로 다시 그려도 다시 부르지 않고, 기한이 바뀌면 그 기한의 0 에서 한 번 더 부른다', (tester) async {
      var calls = 0;
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      await pump(tester, past, () => calls++);
      await tester.pump();
      await pump(tester, past, () => calls++);
      await tester.pump();
      expect(calls, 1);

      await pump(tester, past.subtract(const Duration(days: 1)), () => calls++);
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('0 이 되기 전에 화면에서 빠지면 부르지 않는다', (tester) async {
      var calls = 0;
      await pump(tester, DateTime.now().add(const Duration(milliseconds: 300)), () => calls++);
      await tester.pumpWidget(const SizedBox());

      await elapse(tester, const Duration(milliseconds: 500), ticks: 2);
      expect(calls, 0);
    });
  });
}
