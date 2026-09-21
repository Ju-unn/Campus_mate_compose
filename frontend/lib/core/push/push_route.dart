import 'package:campus_mate/core/router/app_routes.dart';

/// 푸시 `data.route`(Task B3)를 앱 경로로 바꾼다.
/// 모르는 값이면 null 을 돌려주고 **아무 데도 보내지 않는다** — 알림 하나 때문에
/// 사용자가 보던 화면을 빼앗지 않는다.
abstract final class PushRoute {
  static String? resolve(Map<String, dynamic> data) => switch (data['route']) {
        'daily_card' => AppRoutes.today,
        // 받은 수락도 매칭 성사도 지금은 대화 목록(13)이 종착지다. 채팅방은 조각 5.
        'acceptances' || 'match' => AppRoutes.conversations,
        _ => null,
      };
}
