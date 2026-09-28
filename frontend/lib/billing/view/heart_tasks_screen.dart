import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// pen `EJDsZ`. 초기값 기준 안내(DESIGN §8.10 표) — 줄의 하트 수는 서버 값이다.
const String _rewardNotice = '초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트';

/// pen `NYgh7` 여백 [8,16,32,16].
const EdgeInsets _listPadding = EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl);

/// 18a 무료로 하트 모으기(pen `qyUgZ`). 설정(16)에서 들어온다.
class HeartTasksScreen extends ConsumerWidget {
  const HeartTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(heartTasksViewModelProvider);
    return Scaffold(
      // pen `Q9II4` 56, 좌우 16, 간격 12, 뒤로 24. 누름 48(대장)이라 왼쪽 4 + 48 — 아이콘은 x16, 제목은 x52 그대로.
      appBar: AppBar(
        toolbarHeight: 56,
        leadingWidth: 52,
        titleSpacing: 0,
        leading: Navigator.of(context).canPop()
            // AppBar 의 leading 칸은 toolbarHeight 에 맞춰 세로로 늘어난다(NavigationToolbar 가 높이를 tight 로
            // 준다). Align 으로 느슨한 제약을 다시 줘야 버튼이 pen 대로 48 로 남는다(브리프 코드는 56 이 됐다).
            ? Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xxs),
                  child: IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(AppIcons.arrowLeft, size: 24, color: AppColors.ink),
                  ),
                ),
              )
            : null,
        title: Text(
          '무료로 하트 모으기',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.headline.copyWith(color: AppColors.ink),
        ),
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, HeartTasksUiState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final errorMessage = state.errorMessage;
    if (errorMessage != null) {
      return _LoadError(message: errorMessage, onRetry: () => ref.invalidate(heartTasksViewModelProvider));
    }
    return ListView(
      padding: _listPadding,
      children: [
        Text(_rewardNotice, style: AppTypography.caption.copyWith(color: AppColors.muted)),
        // pen 섹션 간격 8 + 빈칸 `vlmhj` 8 + 간격 8.
        const SizedBox(height: AppSpacing.lg),
        for (final (index, task) in state.tasks.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xs),
          HeartTaskRow(task: task, onTap: _onTap(context, task)),
        ],
      ],
    );
  }

  /// 누르는 줄: 인증 항목의 미완료 · 반려(→ 18b, 반려면 사유를 실어 18b-2), 투표 미완료(→ 커뮤니티 탭).
  VoidCallback? _onTap(BuildContext context, HeartTask task) {
    if (!task.kind.needsProof) {
      return task.state == HeartTaskState.open ? () => context.go(AppRoutes.community) : null;
    }
    return switch (task.state) {
      HeartTaskState.open => () => context.push(heartTaskSubmitLocation(task.kind)),
      HeartTaskState.rejected => () => context.push(heartTaskSubmitLocation(task.kind, task.rejectReason)),
      HeartTaskState.reviewing || HeartTaskState.done => null,
    };
  }
}

/// 읽기 실패. pen 에 없는 상태 — 16f 차단 목록과 같은 회색 문구에 "다시 시도" 를 붙인다.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.muted)),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
