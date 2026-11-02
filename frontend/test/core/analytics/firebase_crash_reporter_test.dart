import 'dart:async';

import 'package:campus_mate/core/analytics/firebase_crash_reporter.dart';
import 'package:campus_mate/core/analytics/handled_api_error.dart';
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

  group('앱이 버틴 API 오류', () {
    final url = Uri.parse('https://api.test/chat/matches/11111111-1111-4111-8111-111111111111/messages?limit=1');

    test('비치명(fatal: false)으로 기록하고, 담긴 것은 종류 · 상태 · 경로 패턴뿐이다', () async {
      final error = HandledApiError.fromStatus(503, url);

      reporter.recordHandledError(error);
      await pumpEventQueue();

      final recorded = verify(() => crashlytics.recordError(captureAny<dynamic>(), any(), fatal: false)).captured.single;
      expect(recorded, same(error));
      expect(recorded.toString(), 'HandledApiError(kind: ServerError, status: 503, route: /chat/matches/:id/messages)');
      expect(recorded.toString(), isNot(contains('11111111')));
      expect(recorded.toString(), isNot(contains('limit')));
    });

    test('기록해도 수집을 켜지 않고 사용자 식별값 · 사용자 정의 키도 달지 않는다 — 켜는 것은 enableAfterConsent 뿐', () async {
      reporter.recordHandledError(HandledApiError.fromStatus(500, url));
      await pumpEventQueue();

      verifyNever(() => crashlytics.setCrashlyticsCollectionEnabled(true));
      verifyNever(() => crashlytics.setUserIdentifier(any()));
      verifyNever(() => crashlytics.setCustomKey(any(), any()));
    });

    test('Crashlytics 가 던져도 API 흐름으로 올리지 않는다', () async {
      when(() => crashlytics.recordError(any<dynamic>(), any(), fatal: any(named: 'fatal')))
          .thenAnswer((_) async => throw StateError('플랫폼 오류'));

      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        reporter.recordHandledError(HandledApiError.fromStatus(500, url));
        await pumpEventQueue();
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
    });
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
