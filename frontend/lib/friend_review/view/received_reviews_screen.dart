import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_ui_state.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 화면 문구 — pen HWM2G(값표 B §2).
const _title = '받은 리뷰'; // pen kyDqZ
const _notice = '받은 리뷰는 직접 삭제할 수 없어요. 부적절한 내용은 신고해주세요.'; // pen OHJVi
// pen 에 없는 문구(대장 09-29). 리뷰 신고는 차단하지 않아(P1) 기존 신고 문구("차단되어…")를 쓰지 않는다.
const _reportedMessage = '신고했어요. 운영팀이 확인할게요';
const _emptyTitle = '아직 받은 리뷰가 없어요'; // 계획서 A6

/// pen `geD87` 본문 여백 [8,16,24,16].
const EdgeInsets _bodyPadding = EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.lg);

const ({FriendReviewListSource source, String? profileId}) _received =
    (source: FriendReviewListSource.received, profileId: null);

/// 20c 받은 리뷰(pen `HWM2G`). 15 "친구들이 본 나" 에서 push 로, 새 리뷰 푸시에서 `go` 로 연다.
/// 받은 사람은 지울 수 없고 신고만 한다 — 신고해도 차단하지 않고 카드는 그대로 둔다(P1 · 결정 3).
class ReceivedReviewsScreen extends ConsumerWidget {
  const ReceivedReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendReviewListViewModelProvider(_received));
    return PopScope(
      // 푸시로 바로 열면 스택이 한 장이라 시스템 뒤로가기가 앱을 닫는다 — 화살표와 같은 길로 보낸다(백로그 23).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit(context);
      },
      child: Scaffold(
        // pen `Ho9RC` 56, 여백 [0,8], 간격 4 — 뒤로 `miO1L` 48(arrow-left 22), 제목 x60. 하단 내비 없음.
        appBar: AppBar(
          leadingWidth: 56,
          titleSpacing: AppSpacing.xxs,
          leading: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => _exit(context),
              icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
            ),
          ),
          title: Text(_title, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        ),
        body: SafeArea(child: _body(context, ref, state)),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, FriendReviewListUiState state) {
    if (state.reviews.isNotEmpty) {
      return ListView(
        padding: _bodyPadding,
        children: [
          const FriendReviewNotice(text: _notice),
          // pen geD87 간격 16(안내 → 카드, 카드 사이).
          for (final review in state.reviews) ...[
            const SizedBox(height: AppSpacing.md),
            FriendReviewCard(review: review, onReport: () => _report(context, review.id)),
          ],
        ],
      );
    }
    // pen 에 없는 상태(대장 4) — 안내 상자는 늘 두고 그 아래를 16f 와 같은 모양으로 채운다.
    return Padding(
      padding: _bodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FriendReviewNotice(text: _notice),
          Expanded(child: _placeholder(ref, state)),
        ],
      ),
    );
  }

  Widget _placeholder(WidgetRef ref, FriendReviewListUiState state) {
    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    final error = state.errorMessage;
    if (error != null) {
      return _LoadError(message: error, onRetry: () => ref.invalidate(friendReviewListViewModelProvider(_received)));
    }
    return const _Empty();
  }

  /// 기존 신고 시트를 그대로 띄운다. 어느 결과든 이 화면에 남고 카드도 그대로다 — `reportThenLeave` 는
  /// 차단을 전제로 대화 목록으로 떠나서 쓰지 않는다. 신고됨만 문구를 바꾸고 나머지는 시트가 준 문구 그대로.
  static Future<void> _report(BuildContext context, String reviewId) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showReportSheet(context, ReportTarget.friendReview(reviewId));
    if (result == null) return;
    showSafetyToast(messenger, result.outcome == ReportOutcome.reported ? _reportedMessage : result.message);
  }

  /// 15 에서 push 로 왔으면 돌아가고, 푸시로 바로 열려 돌아갈 곳이 없으면 입구(15 나 탭)로 간다.
  static void _exit(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go(AppRoutes.myProfile);
  }
}

/// 빈 상태 — pen 에 없어 16f 차단 목록 빈 상태(`KLSeQ`)와 같은 모양: 마스코트 120 → 24 → 제목 17/600.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl, horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/mascot-female.png', width: 120, height: 120),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _emptyTitle,
              textAlign: TextAlign.center,
              style: AppTypography.subtitle.copyWith(color: AppColors.ink, height: 25 / 17),
            ),
          ],
        ),
      ),
    );
  }
}

/// 읽기 실패. pen 에 없는 상태 — 16f · 14c 와 같은 회색 문구에 "다시 시도" 를 붙인다.
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
