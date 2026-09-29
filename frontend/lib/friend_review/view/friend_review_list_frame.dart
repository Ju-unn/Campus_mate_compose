import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_ui_state.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// pen `geD87` · `K2HbU` 본문 여백 [8,16,24,16].
const EdgeInsets _bodyPadding = EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.lg);

/// 20c 받은 리뷰(pen `HWM2G`) · 20e 내가 쓴 리뷰(사본 `FEysN`)가 같이 쓰는 틀: 앱바 → 안내 상자 → 카드 목록.
/// 읽는 중 · 실패 · 빈 상태는 안내 상자 아래를 채운다. 카드 오른쪽 동작만 화면마다 다르다([cardBuilder]).
/// 15 에서 push 로 오면 뒤로 = 돌아가기, 푸시 알림으로 바로 열려 돌아갈 곳이 없으면 뒤로 = 15.
class FriendReviewListFrame extends ConsumerWidget {
  const FriendReviewListFrame({
    required this.title,
    required this.notice,
    required this.source,
    required this.cardBuilder,
    required this.empty,
    super.key,
  });

  final String title;
  final String notice;
  final FriendReviewListSource source;
  final Widget Function(BuildContext context, FriendReview review) cardBuilder;
  final Widget empty;

  ({FriendReviewListSource source, String? profileId}) get _args => (source: source, profileId: null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendReviewListViewModelProvider(_args));
    return PopScope(
      // 푸시로 바로 열면 스택이 한 장이라 시스템 뒤로가기가 앱을 닫는다 — 화살표와 같은 길로 보낸다(백로그 23).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit(context);
      },
      child: _RefreshOnEnter(
        args: _args,
        child: Scaffold(
          // pen `Ho9RC` · `AcgUb` 56, 여백 [0,8], 간격 4 — 뒤로 `miO1L` · `X96tq` 48(arrow-left 22), 제목 x60. 하단 내비 없음.
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
            title: Text(title, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
          ),
          body: SafeArea(child: _body(context, ref, state)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, FriendReviewListUiState state) {
    if (state.reviews.isNotEmpty) {
      return ListView(
        padding: _bodyPadding,
        children: [
          FriendReviewNotice(text: notice),
          // pen geD87 · K2HbU 간격 16(안내 → 카드, 카드 사이).
          for (final review in state.reviews) ...[const SizedBox(height: AppSpacing.md), cardBuilder(context, review)],
        ],
      );
    }
    // pen 에 없는 상태(대장 4) — 안내 상자는 늘 두고 그 아래(간격 16 뒤 — 20e-1 `QlDBt` 자리)를 채운다.
    return Padding(
      padding: _bodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FriendReviewNotice(text: notice),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: _placeholder(ref, state)),
        ],
      ),
    );
  }

  Widget _placeholder(WidgetRef ref, FriendReviewListUiState state) {
    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    final error = state.errorMessage;
    if (error != null) {
      return _LoadError(message: error, onRetry: () => ref.invalidate(friendReviewListViewModelProvider(_args)));
    }
    return empty;
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

/// 빈 상태(Empty `TVc8b` 모양 — 16f `KLSeQ` · 20e-1 `QlDBt`): 마스코트 120 → 24 → 제목 17/600 → 8 → 설명, 가운데.
/// 글자를 키워 칸을 넘치면 스크롤한다.
class FriendReviewEmpty extends StatelessWidget {
  const FriendReviewEmpty({required this.mascot, required this.title, this.description, super.key});

  final String mascot;
  final String title;

  /// null 이면 제목까지만(20c — pen 에 없는 상태).
  final String? description;

  @override
  Widget build(BuildContext context) {
    final description = this.description;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl, horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(mascot, width: 120, height: 120),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              // pen `ZBzIg` 17/600, 줄높이 속성 없음 · 렌더 25.
              style: AppTypography.subtitle.copyWith(color: AppColors.ink, height: 25 / 17),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                description,
                textAlign: TextAlign.center,
                // pen `DFs55` 14 / 보통 / muted / 1.55.
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 화면에 들어올 때 한 번 다시 읽는다. 15 지인 리뷰 칸이 같은 목록을 쥐고 있으면 목록이 버려지지 않아,
/// 푸시로 열어도 옛 목록이 남는다(검토 필수 1). 목록은 둔 채 읽어 깜빡이지 않는다.
class _RefreshOnEnter extends ConsumerStatefulWidget {
  const _RefreshOnEnter({required this.args, required this.child});

  final ({FriendReviewListSource source, String? profileId}) args;
  final Widget child;

  @override
  ConsumerState<_RefreshOnEnter> createState() => _RefreshOnEnterState();
}

class _RefreshOnEnterState extends ConsumerState<_RefreshOnEnter> {
  @override
  void initState() {
    super.initState();
    ref.read(friendReviewListViewModelProvider(widget.args).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
