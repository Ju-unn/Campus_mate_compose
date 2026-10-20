import 'dart:async';

import 'package:campus_mate/core/analytics/analytics_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// 진짜 Firebase Analytics. `Firebase.initializeApp()` 이 끝난 뒤에만 만든다(main.dart).
/// 이벤트는 쏘고 잊는다 — 통계가 실패해도 앱 흐름으로 오류를 올리지 않는다(오류 종류만 로그).
class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService(this._analytics);

  final FirebaseAnalytics _analytics;
  final _LoginBeforeConsent _login = _LoginBeforeConsent();

  @override
  void enableAfterConsent() {
    final waitingLogin = _login.startCollecting();
    _fire(() async {
      await _analytics.setAnalyticsCollectionEnabled(true);
      // 로그인은 약관 동의보다 먼저라 그때는 수집이 꺼져 있었다 — 켠 다음에야 보낼 수 있다.
      if (waitingLogin != null) await _sendLogin(waitingLogin);
    });
  }

  @override
  void disable() {
    _login.stopCollecting();
    _fire(() => _analytics.setAnalyticsCollectionEnabled(false));
  }

  @override
  void logLogin(String method) {
    if (!_login.admit(method)) return;
    _fire(() => _sendLogin(method));
  }

  Future<void> _sendLogin(String method) => _analytics.logEvent(name: 'login', parameters: {'method': method});

  @override
  void logOnboardingComplete() => _fire(() => _analytics.logEvent(name: 'onboarding_complete'));

  @override
  void logChatRequestSent() => _fire(() => _analytics.logEvent(name: 'chat_request_sent'));

  @override
  void logHeartPurchase(String productId) =>
      _fire(() => _analytics.logEvent(name: 'heart_purchase', parameters: {'product_id': productId}));

  @override
  void logScreen(String name) => _fire(() => _analytics.logScreenView(screenName: name));

  void _fire(Future<void> Function() action) {
    unawaited(action().catchError((Object error) => debugPrint('사용 통계 실패: ${error.runtimeType}')));
  }
}

/// 수집이 켜졌는지와, 켜지기 전에 한 로그인 하나를 들고 있는다.
/// 로그인(소셜 로그인 성공)은 약관 동의(02-c)보다 먼저 일어난다 — 그때는 수집이 꺼져 있어 바로 보내면 사라진다.
/// 동의 전에 여러 번 로그인했으면 마지막 것만 남는다(같은 기기에서 가장 최근 로그인이 이번 사용 기록이다).
class _LoginBeforeConsent {
  bool _collecting = false;
  String? _waitingMethod;

  /// 지금 바로 보내도 되면 true. 아니면 기억해 두고 false.
  bool admit(String method) {
    if (_collecting) return true;
    _waitingMethod = method;
    return false;
  }

  /// 수집이 켜졌다. 기다리던 로그인이 있으면 돌려주고 비운다.
  String? startCollecting() {
    _collecting = true;
    final method = _waitingMethod;
    _waitingMethod = null;
    return method;
  }

  /// 수집이 꺼졌다. 기다리는 로그인은 지우지 않는다 — 새 사용자가 로그인한 직후(02-c 앞)에도 이 호출이 오기 때문이다.
  void stopCollecting() => _collecting = false;
}
