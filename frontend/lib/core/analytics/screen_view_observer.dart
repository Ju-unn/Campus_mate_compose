import 'package:campus_mate/core/analytics/analytics_service.dart';
import 'package:flutter/widgets.dart';

/// 화면이 바뀔 때 화면 이름을 `screen_view` 로 남긴다. go_router 의 `observers` 에 단다(`AppRouter.create`).
///
/// 이름은 **경로 패턴**(`/chat/:matchId`)이다 — 라우터가 페이지 이름에 `GoRouterState.fullPath` 를 실어 주므로
/// 경로 변수에 든 id(채팅방 · 카드 · 상대 프로필)가 섞이지 않는다. 이름이 없는 길(바닥 시트 · 대화상자)은 남기지 않는다.
class ScreenViewObserver extends NavigatorObserver {
  ScreenViewObserver(this._analytics);

  final AnalyticsService _analytics;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _log(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _log(newRoute);

  /// 이름 있는 화면이 걷히면 그 밑에 있던 화면이 다시 보인다. 이름 없는 길(바닥 시트 · 대화상자)이 닫힐 때는 아래 화면이
  /// 계속 보이던 것이라 새 화면 조회가 아니다 — 기록하지 않는다.
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == null) return;
    _log(previousRoute);
  }

  void _log(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return;
    _analytics.logScreen(name);
  }
}
