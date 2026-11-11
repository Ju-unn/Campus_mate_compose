import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/empty_notice.dart';
import 'package:campus_mate/common/widgets/full_screen_notice.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/push/push_refresh.dart';
import 'package:campus_mate/core/push/push_route.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/notifications/model/data/app_notification.dart';
import 'package:campus_mate/notifications/view/notification_row.dart';
import 'package:campus_mate/notifications/viewmodel/notifications_ui_state.dart';
import 'package:campus_mate/notifications/viewmodel/notifications_view_model.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 줄의 "지금" — 테스트가 고정한다(`communityNowProvider` 와 같은 이음매).
final notificationsNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 테스트가 pen 크기를 재는 데 쓰는 자리 표시.
const Key notificationEmptyIconKey = ValueKey('notification-empty-icon');
const Key notificationErrorIconKey = ValueKey('notification-error-icon');
const Key notificationSkeletonRowKey = ValueKey('notification-skeleton-row');
const Key notificationSkeletonAvatarKey = ValueKey('notification-skeleton-avatar');

/// 목록 끝까지 남은 길이가 이보다 짧아지면 다음 쪽을 읽는다.
const double _loadMoreExtent = 300;

/// 09c 알림함(pen `WiGM2` 목록 · `fANzR` 빈 상태 · `vGd3l` 불러오기 실패 · `QUfcS` 로딩).
/// 홈 종 아이콘이 `push` 로 연다. 하단 내비는 없다(하위 화면 관례).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsViewModelProvider);
    final hasUnread = ref.watch(unreadCountProvider) > 0;
    return Scaffold(
      // pen `XG5nM`(AppBar · Sub `KH1hX`) 높이 56 · 좌우 여백 12 · 간격 4 — 뒤로 `ftxse` 48 이 x12, 제목 `YSMvI` 가 x64, 오른쪽 글자 버튼 `q7PN8` 이 x268~348.
      appBar: AppBar(
        leadingWidth: 60,
        titleSpacing: AppSpacing.xxs,
        centerTitle: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          // leading 칸은 높이가 56 으로 고정이라 Align 으로 느슨하게 풀어야 화살표 칸이 48×48 로 나온다.
          child: Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => _exit(context),
              icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
            ),
          ),
        ),
        title: Text(context.l10n.notificationsScreenTitle, style: AppTypography.subNavTitle.copyWith(color: AppColors.ink)),
        actions: [
          // "모두 읽음" 은 목록 모습에서만(빈 상태 · 실패 · 로딩에는 없다). 안 읽은 게 없으면 누를 일이 없어 숨긴다 — pen 에 없는 상태.
          if (state.phase == NotificationsPhase.list && hasUnread)
            TextButton(
              onPressed: ref.read(notificationsViewModelProvider.notifier).markAllRead,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryText,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              // pen `CkuaM` 14 / 600 / primary-text.
              child: Text(context.l10n.notificationsMarkAllRead, style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText)),
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, NotificationsUiState state) {
    return switch (state.phase) {
      NotificationsPhase.loading => const _Skeleton(),
      NotificationsPhase.empty => const _Empty(),
      NotificationsPhase.failed => _Failed(onRetry: ref.read(notificationsViewModelProvider.notifier).retry),
      NotificationsPhase.list => _List(state: state, onTap: (item) => _open(context, ref, item)),
    };
  }

  /// 읽음 처리(기다리지 않는다) → 푸시와 같은 경로 규칙으로 이동. 갈 곳을 모르면 이 화면에 남는다.
  /// 경로는 `PushRoute.resolve` 를 그대로 쓰고, 알림을 눌러 앱을 열 때처럼 그 화면의 목록도 새로 읽는다(`main.dart _openRoute` 와 같은 순서).
  void _open(BuildContext context, WidgetRef ref, AppNotification item) {
    final viewModel = ref.read(notificationsViewModelProvider.notifier);
    final path = PushRoute.resolve(item.data);
    viewModel.markRead(item.id);
    if (path == null) return;
    refreshForPush(ref.read, item.data, invalidate: ref.invalidate, exists: ref.exists);
    if (_replacesInbox(path)) {
      context.go(path);
    } else {
      context.push(path);
    }
  }

  /// 탭 · 홈 위 시트 경로(오늘의 카드, 대화 목록, 지인 리뷰 쓰기)는 `go` 로 바꿔 알림함을 닫는다 —
  /// 하단 내비 탭은 쌓는 화면이 아니고, 리뷰 쓰기는 홈 위에 시트로 뜨는 경로(`/home/...`)다.
  /// 그 밖(채팅방 · 받은 리뷰 · 학생증 등)은 알림함 위에 쌓아 뒤로가기가 알림함으로 돌아오게 한다.
  static bool _replacesInbox(String path) =>
      path == AppRoutes.today ||
      path == AppRoutes.conversations ||
      path.startsWith('${AppRoutes.friendReviewWrite}/');

  /// 홈에서 push 로 왔으면 돌아가고, 돌아갈 곳이 없으면 홈으로 간다.
  static void _exit(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go(AppRoutes.home);
  }
}

/// pen `CHPNj` — 좌우 여백 16, 위 0. 아래로 끌어 새로고침 · 끝에 닿으면 다음 쪽.
class _List extends ConsumerWidget {
  const _List({required this.state, required this.onTap});

  final NotificationsUiState state;
  final void Function(AppNotification item) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(notificationsNowProvider)();
    final viewModel = ref.read(notificationsViewModelProvider.notifier);
    final items = state.items;
    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < _loadMoreExtent) viewModel.loadMore();
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: items.length + (state.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            final item = items[index];
            return NotificationRow(
              item: item,
              now: now,
              onTap: () => onTap(item),
              showDivider: index < items.length - 1 || state.nextBefore != null,
            );
          },
        ),
      ),
    );
  }
}

/// 빈 상태(pen `fANzR`): 본문 [0,24,40,24], 위 여백 120, 안내(`HM61F` = Empty `TVc8b`) 여백 [48,24]·가운데.
/// 글자를 키워 칸을 넘치면 스크롤한다.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 120),
        child: EmptyNotice(
          align: EmptyNoticeAlign.top,
          // `mH9oC` = 3D 알림 `WyOg1` 120.
          image: const Icon3d(AppIcon3d.bell, size: 120, key: notificationEmptyIconKey),
          title: context.l10n.notificationsEmptyTitle,
          description: context.l10n.notificationsEmptyBody,
        ),
      ),
    );
  }
}

/// 불러오기 실패(pen `vGd3l`, 01-1 인터넷 없음 `NWGuf` 와 같은 패턴): 안내는 위 여백 120 아래, "다시 시도"(`TMLwr`)는 바닥 쪽.
class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FullScreenNotice(
      notice: EmptyNotice(
        align: EmptyNoticeAlign.top,
        // `AeOMJ` = 3D 안내 `s3b4k` 120.
        image: const Icon3d(AppIcon3d.infoBlue, size: 120, key: notificationErrorIconKey),
        title: context.appErrorText(AppError.notificationsLoad),
        description: context.appErrorText(AppError.tryLater),
        // 큰 안내 제목 20/700 줄높이 1.5(렌더 30, pen `vGd3l`). 설명은 Empty 마스터 값 그대로.
        titleStyle: EmptyNotice.largeTitleStyle,
      ),
      button: AppButton(label: context.l10n.commonRetry, onPressed: onRetry),
    );
  }
}

/// 로딩(pen `QUfcS`): Skeleton · ChatRow `zrbLn` 5줄(328×72), 줄 사이 1px 선. 원 44 · 막대 모서리 6 · 색 #EBEBEB.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.notificationsLoadingLabel,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
              const _SkeletonRow(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  static Widget _bar(double width, double height) => SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.hairlineSoft, borderRadius: BorderRadius.circular(6)), // pen 막대 모서리 6, 토큰 밖
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: notificationSkeletonRowKey,
      height: 72,
      child: Stack(
        children: [
          // `tNA3z` 원 44 (x0 · y14).
          const Positioned(
            left: 0,
            top: 14,
            child: SizedBox.square(
              key: notificationSkeletonAvatarKey,
              dimension: 44,
              child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.hairlineSoft)),
            ),
          ),
          // `uEzRX` 이름 80×16 · 미리보기 180×13 (x56 · y18.5, 사이 6).
          Positioned(left: 56, top: 18.5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_bar(80, 16), const SizedBox(height: 6), _bar(180, 13)])),
          // `jmhNV` 시간 44×12, 오른쪽 끝 · y30.
          Positioned(right: 0, top: 30, child: _bar(44, 12)),
        ],
      ),
    );
  }
}
