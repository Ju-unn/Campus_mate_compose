import 'package:campus_mate/core/router/app_routes.dart';

/// 푸시 `data.route`(Task B3)를 앱 경로로 바꾼다.
/// 모르는 값이면 null 을 돌려주고 **아무 데도 보내지 않는다** — 알림 하나 때문에
/// 사용자가 보던 화면을 빼앗지 않는다.
abstract final class PushRoute {
  static String? resolve(Map<String, dynamic> data) => switch (data['route']) {
        'daily_card' => AppRoutes.today,
        // 받은 수락도 매칭 성사도 대화 목록(13)이 종착지다 — 방은 목록에서 골라 들어간다.
        'acceptances' || 'match' => AppRoutes.conversations,
        // 새 메시지·신뢰 확인 리마인드·공개 알림은 그 방으로 바로 보낸다.
        'chat' => _chatRoom(data),
        _ => null,
      };

  /// 방 id 가 없거나 모양이 이상하면 목록으로 보낸다 — 엉뚱한 방을 여는 것보다 낫다.
  static String _chatRoom(Map<String, dynamic> data) {
    final matchId = data['match_id'];
    return matchId is String && matchId.isNotEmpty
        ? '${AppRoutes.chatRoom}/$matchId'
        : AppRoutes.conversations;
  }
}
