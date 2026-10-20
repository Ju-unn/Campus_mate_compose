import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/analytics/collection_consent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_analytics_service.dart';
import 'fake_crash_reporter.dart';
import 'fake_performance_monitor.dart';

void main() {
  late FakeAnalyticsService analytics;
  late FakeCrashReporter crashReporter;
  late FakePerformanceMonitor performance;
  late CollectionConsent consent;

  CollectionConsent makeConsent() {
    analytics = FakeAnalyticsService();
    crashReporter = FakeCrashReporter();
    performance = FakePerformanceMonitor();
    return CollectionConsent([analytics, crashReporter, performance]);
  }

  setUp(() => consent = makeConsent());

  // 셋은 늘 같이 켜지고 같이 꺼진다 — 하나만 켜진 채 남으면 동의 전 수집이 된다.
  void expectAll(bool collecting) {
    expect(analytics.collecting, collecting);
    expect(crashReporter.collecting, collecting);
    expect(performance.collecting, collecting);
  }

  test('처음에는 아무것도 켜지 않는다', () {
    expectAll(false);
    expect(analytics.calls, isEmpty);
    expect(crashReporter.calls, isEmpty);
    expect(performance.calls, isEmpty);
  });

  test('약관 동의 전 관문(02-c)에서는 로그인한 사람도 켜지 않고 끈다', () {
    for (final gate in [VerificationGate.needsConsent, VerificationGate.needsConsentRenewal]) {
      consent.sync(isAuthenticated: true, gate: gate);
      expect(analytics.calls.last, 'disable', reason: '$gate');
      expect(crashReporter.calls.last, 'disable', reason: '$gate');
      expect(performance.calls.last, 'disable', reason: '$gate');
    }
    expectAll(false);
  });

  test('동의를 마쳐 다음 관문(학교 메일)으로 넘어가면 켠다', () {
    consent.sync(isAuthenticated: true, gate: VerificationGate.needsConsent);
    consent.sync(isAuthenticated: true, gate: VerificationGate.needsSchoolEmail);

    expectAll(true);
  });

  test('동의 뒤의 어느 관문이든 켠다 — 앱을 켤 때 이미 동의를 마친 사람도 같다', () {
    const afterConsent = [
      VerificationGate.needsSchoolEmail,
      VerificationGate.needsVerificationMethod,
      VerificationGate.needsSchoolEmailChosen,
      VerificationGate.needsGraduateApplication,
      VerificationGate.graduateReviewing,
      VerificationGate.needsSchoolInfo,
      VerificationGate.complete,
    ];
    for (final gate in afterConsent) {
      makeConsent().sync(isAuthenticated: true, gate: gate);
      expectAll(true);
    }
  });

  test('로그아웃(세션 없음)이면 관문 값이 무엇이든 끈다', () {
    consent.sync(isAuthenticated: true, gate: VerificationGate.complete);
    consent.sync(isAuthenticated: false, gate: VerificationGate.complete);

    expectAll(false);
  });

  test('아직 모르는 동안(조회 중 · 인터넷 없음)은 켜지도 끄지도 않는다 — 켜진 채면 그대로, 꺼진 채면 그대로', () {
    consent.sync(isAuthenticated: true, gate: VerificationGate.unknown);
    consent.sync(isAuthenticated: true, gate: VerificationGate.unreachable);
    expect(analytics.calls, isEmpty);
    expect(crashReporter.calls, isEmpty);
    expect(performance.calls, isEmpty);

    consent.sync(isAuthenticated: true, gate: VerificationGate.complete);
    consent.sync(isAuthenticated: true, gate: VerificationGate.unknown);
    expectAll(true);
  });
}
