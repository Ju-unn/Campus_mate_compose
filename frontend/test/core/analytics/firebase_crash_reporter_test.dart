import 'dart:async';

import 'package:campus_mate/core/analytics/firebase_crash_reporter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCrashlytics extends Mock implements FirebaseCrashlytics {}

void main() {
  late _MockCrashlytics crashlytics;
  late FirebaseCrashReporter reporter;

  setUpAll(() => registerFallbackValue(FlutterErrorDetails(exception: 'x')));

  setUp(() {
    crashlytics = _MockCrashlytics();
    when(() => crashlytics.setCrashlyticsCollectionEnabled(any())).thenAnswer((_) async {});
    when(() => crashlytics.recordFlutterFatalError(any())).thenAnswer((_) async {});
    when(() => crashlytics.recordError(any<dynamic>(), any(), fatal: any(named: 'fatal'))).thenAnswer((_) async {});
    reporter = FirebaseCrashReporter(crashlytics);
  });

  test('동의 뒤 켜면 수집을 켜고, 끄면 수집을 끈다', () async {
    reporter.enableAfterConsent();
    reporter.disable();
    await pumpEventQueue();

    verifyInOrder([
      () => crashlytics.setCrashlyticsCollectionEnabled(true),
      () => crashlytics.setCrashlyticsCollectionEnabled(false),
    ]);
  });

  test('프레임워크 오류는 Crashlytics 의 치명 오류로 넘긴다', () async {
    final details = FlutterErrorDetails(exception: StateError('깨짐'));

    reporter.recordFlutterFatalError(details);
    await pumpEventQueue();

    verify(() => crashlytics.recordFlutterFatalError(details)).called(1);
  });

  test('잡히지 않은 비동기 오류는 fatal 로 기록한다', () async {
    final error = StateError('깨짐');
    final stack = StackTrace.current;

    reporter.recordFatalError(error, stack);
    await pumpEventQueue();

    verify(() => crashlytics.recordError(error, stack, fatal: true)).called(1);
  });

  test('사용자 식별값이나 사용자 정의 키는 어디에도 보내지 않는다', () async {
    reporter.enableAfterConsent();
    reporter.recordFatalError(StateError('깨짐'), StackTrace.current);
    await pumpEventQueue();

    verifyNever(() => crashlytics.setUserIdentifier(any()));
    verifyNever(() => crashlytics.setCustomKey(any(), any()));
  });

  test('Crashlytics 가 던져도 오류 처리기 안에서 다시 던지지 않는다', () async {
    when(() => crashlytics.recordError(any<dynamic>(), any(), fatal: any(named: 'fatal')))
        .thenAnswer((_) async => throw StateError('플랫폼 오류'));

    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      reporter.recordFatalError(StateError('깨짐'), StackTrace.current);
      await pumpEventQueue();
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });
}
