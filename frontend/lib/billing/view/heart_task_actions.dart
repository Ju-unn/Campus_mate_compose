import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 무료 하트 안내 — 18a(pen `EJDsZ`)와 하트 스토어(18) "무료로 모으기"(pen `cVVgB`)가 같이 쓴다. 12/400 muted 줄높이 1.4.
/// 셋째 줄(투표 지급 기준, 서버 cast_poll_vote 와 같다)은 대장 결정 10-12 로 더했다 — pen 은 아직 두 줄이다(동기화 대기).
/// 줄의 하트 수는 서버 값이고, 여기 숫자는 DESIGN §8.10 표의 기준이다.
const String heartRewardNotice =
    '초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트\n커뮤니티 투표 하루 첫 투표 1번만 10 · 한 주 최대 30 하트';

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
