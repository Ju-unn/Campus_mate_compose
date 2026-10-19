import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 하트 과제 한 줄을 눌렀을 때 하는 일 — 18a 와 하트 스토어(18)의 "무료로 모으기"가 같이 쓴다.
/// 인증 항목은 서버가 낼 수 있다고 한 때(`canSubmit`: 한도가 남았다 — 단톡방은 검수 중이어도)만 18b 로 간다.
/// 반려 줄이면 사유를 실어 18b-2. 투표 미완료는 커뮤니티 탭. 그 밖에는 누를 곳이 없다(null).
VoidCallback? heartTaskOnTap(BuildContext context, HeartTask task) {
  if (!task.kind.needsProof) {
    return task.state == HeartTaskState.open ? () => context.go(AppRoutes.community) : null;
  }
  if (!task.canSubmit) return null;
  final reason = task.state == HeartTaskState.rejected ? task.rejectReason : null;
  return () => context.push(heartTaskSubmitLocation(task.kind, reason));
}
