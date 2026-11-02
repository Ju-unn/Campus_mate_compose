import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/core/analytics/analytics_service.dart';
import 'package:campus_mate/core/analytics/crash_reporter.dart';
import 'package:campus_mate/core/analytics/handled_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_crash_reporter.dart';

void main() {
  test('기본값은 아무것도 기록하지 않는 구현이다 — 시험이 Firebase 를 켜지 않는다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(analyticsServiceProvider), isA<NoAnalyticsService>());
    expect(container.read(crashReporterProvider), isA<NoCrashReporter>());
  });

  test('앱이 버틴 API 오류 보고기는 지금 오류 수집(crashReporterProvider)에 비치명으로 넘기고 같은 오류는 1분에 한 번이다', () {
    final crash = FakeCrashReporter();
    final container = ProviderContainer(overrides: [crashReporterProvider.overrideWithValue(crash)]);
    addTearDown(container.dispose);
    final reporter = container.read(handledErrorReporterProvider);
    final error = HandledApiError.fromStatus(503, Uri.parse('https://api.test/cards/today'));

    reporter.report(error);
    reporter.report(error);

    expect(crash.calls, ['handled:ServerError:503:/cards/today']);
  });
}
