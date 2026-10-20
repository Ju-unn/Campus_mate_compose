import 'package:campus_mate/core/analytics/analytics_service.dart';
import 'package:campus_mate/core/analytics/collection_consent.dart';
import 'package:campus_mate/core/analytics/crash_reporter.dart';
import 'package:campus_mate/core/analytics/performance_monitor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 기본값은 아무것도 기록하지 않는다 — 시험이 Firebase 를 켜지 않고 앱을 띄운다(`systemNotificationsProvider` 와 같은 방식).
/// 진짜(`FirebaseAnalyticsService`)는 main() 이 `Firebase.initializeApp()` 이 성공했을 때만 덮어쓴다.
/// 로그아웃하면 SessionScope 가 provider 를 새로 만드는데, 그때도 같은 진짜를 쓰도록 overrides 에 값으로 둔다.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) => const NoAnalyticsService());

/// [analyticsServiceProvider] 와 같다 — 오류 수집. 기본값은 아무것도 보고하지 않는다.
final crashReporterProvider = Provider<CrashReporter>((ref) => const NoCrashReporter());

/// [analyticsServiceProvider] 와 같다 — 성능 측정(자동 수집만). 기본값은 아무것도 하지 않는다.
final performanceMonitorProvider = Provider<PerformanceMonitor>((ref) => const NoPerformanceMonitor());

final collectionConsentProvider = Provider<CollectionConsent>(
  (ref) => CollectionConsent([
    ref.read(analyticsServiceProvider),
    ref.read(crashReporterProvider),
    ref.read(performanceMonitorProvider),
  ]),
);
