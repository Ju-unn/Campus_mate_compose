import 'package:campus_mate/core/analytics/crash_reporter.dart';
import 'package:campus_mate/core/analytics/handled_api_error.dart';

/// 앱이 버틴 API 오류를 오류 수집에 넘기되, **같은 오류는 [_gap] 안에 한 번만** 보낸다.
/// 서버가 내려가 있으면 화면마다 폴링이 계속 같은 오류를 내서 하나의 사고가 수백 건으로 부풀기 때문이다.
///
/// shortcut: 마지막으로 보낸 때를 메모리 map 에만 둔다(앱을 껐다 켜면 비워져 한 번 더 간다). 열쇠는 종류 × 상태 × 경로 패턴이라
/// 수십 개를 넘지 않아 지우는 길을 두지 않았다 — 경로 종류가 크게 늘면 오래된 열쇠를 지운다.
class HandledErrorReporter {
  HandledErrorReporter(this._crashReporter, {this._gap = const Duration(minutes: 1), this._now = DateTime.now});

  final CrashReporter _crashReporter;
  final Duration _gap;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastSentAt = {};

  void report(HandledApiError error) {
    final now = _now();
    final last = _lastSentAt[error.key];
    if (last != null && now.difference(last) < _gap) return;
    _lastSentAt[error.key] = now;
    _crashReporter.recordHandledError(error);
  }
}
