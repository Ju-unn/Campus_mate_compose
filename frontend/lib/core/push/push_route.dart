import 'package:campus_mate/billing/model/heart_task.dart';
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
        // 지인 리뷰 — 새 리뷰는 받은 목록, 추천 가입은 그 친구의 리뷰 쓰기. 누구에게 쓸지 모르면 보내지 않는다.
        'friend_reviews' => AppRoutes.friendReviews,
        'friend_review_write' => switch (data['profile_id']) {
            final String id when id.isNotEmpty => '${AppRoutes.friendReviewWrite}/$id',
            _ => null,
          },
        // 인증샷 결과(2026-10-18 "가") — 승인은 18a 목록, 반려는 사유 알림이 뜨는 18b-2 다시 제출.
        'heart_tasks' => AppRoutes.heartTasks,
        'heart_task_retry' => _heartTaskRetry(data),
        // 옛 학생증 검토 결과(`verification`, 2026-10-17 학생증 제거)도 여기로 온다 — 알림함에 남은 줄을 눌러도 무동작.
        _ => null,
      };

  /// 18b-2 경로(`heartTaskSubmitLocation` 과 같은 모양 — 시험이 같음을 못박는다). data 의 task · reason 은 enum 으로 거른 코드만
  /// 경로에 싣는다(#599 경로 id 검사와 같은 원칙). 인증샷 항목이 아니면 18a 로, 사유를 모르면 사유 알림 없는 18b 로 보낸다.
  static String _heartTaskRetry(Map<String, dynamic> data) {
    final task = data['task'];
    final kind = task is String ? HeartTaskKind.tryParse(task) : null;
    if (kind == null || !kind.needsProof) return AppRoutes.heartTasks;
    final reason = data['reason'];
    return Uri(
      path: '${AppRoutes.heartTaskSubmit}/${kind.code}',
      queryParameters: reason is String && HeartTaskRejectReason.tryParse(reason) != null ? {'reason': reason} : null,
    ).toString();
  }

  /// 방 id 가 없거나 모양이 이상하면 목록으로 보낸다 — 엉뚱한 방을 여는 것보다 낫다.
  static String _chatRoom(Map<String, dynamic> data) {
    final matchId = data['match_id'];
    return matchId is String && matchId.isNotEmpty
        ? '${AppRoutes.chatRoom}/$matchId'
        : AppRoutes.conversations;
  }
}
