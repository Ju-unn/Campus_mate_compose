import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 하트 과제 한 줄을 눌렀을 때 하는 일 — 18a 와 하트 스토어(18)의 "무료로 모으기"가 같이 쓴다.
/// 인증 항목의 미완료 · 반려(→ 18b, 반려면 사유를 실어 18b-2), 투표 미완료(→ 커뮤니티 탭). 그 밖에는 누를 곳이 없다(null).
VoidCallback? heartTaskOnTap(BuildContext context, HeartTask task) {
  if (!task.kind.needsProof) {
    return task.state == HeartTaskState.open ? () => context.go(AppRoutes.community) : null;
  }
  return switch (task.state) {
    HeartTaskState.open => () => context.push(heartTaskSubmitLocation(task.kind)),
    HeartTaskState.rejected => () => context.push(heartTaskSubmitLocation(task.kind, task.rejectReason)),
    HeartTaskState.reviewing || HeartTaskState.done => null,
  };
}
