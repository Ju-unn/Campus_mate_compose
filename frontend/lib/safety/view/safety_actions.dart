import 'dart:async';

import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/block_confirm_sheet.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 채팅방(14) · 상대 프로필(14c)이 같이 쓰는 신고 · 차단 흐름. 두 화면의 결과가 같아야 해서 한 곳에 둔다.

/// 조각 6 결과 토스트(pen `yEDB9` = Toast `I8UOWm`). 기본 아이콘은 신고 완료의 circle-check 16.
///
/// 신고 · 차단이 끝나면 화면을 떠나 대화 목록으로 가므로 화면 안 상태가 아니라 앱 전체 ScaffoldMessenger 로 띄운다 —
/// 그래야 목록 화면 위에 남는다. [messenger] 는 화면을 떠나기 전에 잡아 둔다.
void showSafetyToast(ScaffoldMessengerState messenger, String message, {IconData icon = AppIcons.circleCheck}) {
  messenger.showSnackBar(
    SnackBar(
      content: AppToast(leading: Icon(icon, size: 16, color: AppColors.onInk), label: message),
      // pen 토스트 폭 288(전시판 320 안 fill). 글자 칸 232 에서 두 줄로 내려간다.
      width: 288,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      // 04-2 토스트와 같은 3초(pen 에 표시 시간이 없다).
      duration: const Duration(seconds: 3),
    ),
  );
}

/// 신고 시트 → 결과 토스트. 신고하면 차단도 된다(결정 4) — 신고됨 · 이미 신고면 상대가 사라지니 대화 목록으로 간다.
/// 하루 상한 · 대상 없음은 차단이 안 됐거나 할 게 없어 토스트만 띄우고 그 화면에 남는다.
Future<void> reportThenLeave(BuildContext context, WidgetRef ref, ReportTarget target) async {
  // 목록으로 가도 토스트가 남게, 그리고 화면이 닫힌 뒤에는 ref 를 못 쓰니 미리 잡는다.
  final messenger = ScaffoldMessenger.of(context);
  final conversations = ref.read(conversationsViewModelProvider.notifier);
  final result = await showReportSheet(context, target);
  if (result == null || !context.mounted) {
    return;
  }
  showSafetyToast(messenger, result.message);
  if (result.outcome == ReportOutcome.reported || result.outcome == ReportOutcome.alreadyReported) {
    _goToConversations(context, conversations);
  }
}

/// 14e 확인 → 차단 → 대화 목록. 실패하면 서버 문구를 돌려준다 — 보여 주는 자리는 화면마다 다르다.
/// 취소했거나 성공했으면 null.
Future<String?> blockThenLeave(
  BuildContext context,
  WidgetRef ref, {
  required String profileId,
  required String nickname,
}) async {
  final repository = ref.read(safetyRepositoryProvider);
  final conversations = ref.read(conversationsViewModelProvider.notifier);
  if (!await showBlockConfirmSheet(context, nickname) || !context.mounted) {
    return null;
  }
  final result = await repository.block(profileId);
  if (!context.mounted) {
    return null;
  }
  return result.when(
    onSuccess: (_) {
      _goToConversations(context, conversations);
      return null;
    },
    onFailure: (failure) => failure.toDisplayMessage(),
  );
}

/// 차단된 상대의 방은 목록에서 사라진다. 목록을 새로 읽게 하고 목록으로 내려보낸다 —
/// pop 하면 연 곳(매칭 성사 · 채팅방 등)으로 돌아갈 수 있어 `go` 로 목록을 고정한다.
void _goToConversations(BuildContext context, ConversationsViewModel conversations) {
  unawaited(conversations.refresh());
  GoRouter.maybeOf(context)?.go(AppRoutes.conversations);
}
