import 'package:campus_mate/core/analytics/handled_api_error.dart';
import 'package:campus_mate/core/analytics/handled_error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_crash_reporter.dart';

void main() {
  late FakeCrashReporter crash;
  late DateTime clock;
  late HandledErrorReporter reporter;
  final url = Uri.parse('https://api.test/cards/today');

  setUp(() {
    crash = FakeCrashReporter();
    clock = DateTime(2026, 11, 2, 9);
    reporter = HandledErrorReporter(crash, now: () => clock);
  });

  test('오류를 오류 수집에 비치명으로 넘긴다', () {
    reporter.report(HandledApiError.fromStatus(503, url));

    expect(crash.calls, ['handled:ServerError:503:/cards/today']);
  });

  test('같은 오류가 1분 안에 또 오면 한 번만 보낸다', () {
    reporter.report(HandledApiError.fromStatus(503, url));
    clock = clock.add(const Duration(seconds: 59));
    reporter.report(HandledApiError.fromStatus(503, url));

    expect(crash.calls, hasLength(1));
  });

  test('1분이 지나면 같은 오류도 다시 보낸다', () {
    reporter.report(HandledApiError.fromStatus(503, url));
    clock = clock.add(const Duration(minutes: 1));
    reporter.report(HandledApiError.fromStatus(503, url));

    expect(crash.calls, hasLength(2));
  });

  test('종류 · 상태 · 경로 중 하나라도 다르면 따로 센다', () {
    reporter.report(HandledApiError.fromStatus(503, url));
    reporter.report(HandledApiError.fromStatus(500, url));
    reporter.report(HandledApiError.fromStatus(503, Uri.parse('https://api.test/home/summary')));
    reporter.report(HandledApiError.fromException(StateError('x'), url));

    expect(crash.calls, hasLength(4));
  });
}
