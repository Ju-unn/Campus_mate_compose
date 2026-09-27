import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:campus_mate/safety/viewmodel/block_list_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/block_list_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 테스트가 pen 크기를 재는 데 쓰는 자리 표시.
const Key blockedCardKey = ValueKey('blocked-card');
const Key blockedRowKey = ValueKey('blocked-row');
const Key blockedAvatarKey = ValueKey('blocked-avatar');

/// pen `c5ovaJ` · `J2sEcV` 목록 여백 [12,16,24,16].
const EdgeInsets _listPadding = EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg);

/// 16f 차단 목록(pen `Oby6v`, 빈 상태 `KLSeQ`). 들어올 때마다 새로 읽는다(뷰모델이 autoDispose).
class BlockListScreen extends ConsumerWidget {
  const BlockListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(blockListViewModelProvider);
    return Scaffold(
      // pen `S0Th99` 56, 여백 [0,8], 간격 4 — 8 + 48 에 titleSpacing 4 로 화살표 가운데 x32, 제목 x60.
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: 4,
        leading: Navigator.of(context).canPop()
            ? const Padding(padding: EdgeInsets.only(left: 8), child: BackButton(color: AppColors.ink))
            : null,
        title: Text('차단 목록', style: AppTypography.navTitle),
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, BlockListUiState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // 읽기 실패는 줄이 하나도 없을 때뿐이다 — 줄이 있는데 문구가 있으면 해제 실패다.
    if (state.blocks.isEmpty && state.errorMessage != null) {
      return _LoadError(
        message: state.errorMessage!,
        onRetry: () => ref.invalidate(blockListViewModelProvider),
      );
    }
    if (state.blocks.isEmpty) {
      return const _Empty();
    }
    return ListView(
      padding: _listPadding,
      children: [
        Text(
          '차단하면 그 대화는 내 목록에서 사라져요.',
          // pen `z0QE44` 14 / 보통 / muted / 1.5.
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: _gap),
        _BlockedCard(
          blocks: state.blocks,
          isBusy: state.unblockingProfileId != null,
          onUnblock: (user) => _confirmUnblock(context, ref, user),
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          // 해제 실패는 pen 에 없다 — 줄은 그대로 두고 카드 바로 아래 빨간 한 줄로 알린다(신고 시트 실패와 같은 모양).
          Text(
            state.errorMessage!,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: _gap),
        const _ContactNotice(),
      ],
    );
  }

  /// pen 목록 간격 20 은 간격 토큰(md 16 · lg 24) 사이 값이다.
  static const double _gap = 20;

  Future<void> _confirmUnblock(BuildContext context, WidgetRef ref, BlockedUser user) async {
    final viewModel = ref.read(blockListViewModelProvider.notifier);
    final confirmed = await showSafetyConfirmSheet(
      context,
      // pen `zzLKe` · `DVmVy` · `Tcqay` 문구 그대로.
      title: '차단을 해제할까요?',
      description: '이 상대가 다시 카드에 나타날 수 있어요. 사라진 대화는 돌아오지 않아요.',
      confirmLabel: '해제',
    );
    if (confirmed) {
      await viewModel.unblock(user.profileId);
    }
  }
}

/// 차단 목록 카드(pen `JULLG`): 채움 surface-soft, 테두리 hairline 1, 모서리 12, 줄 사이 0.
class _BlockedCard extends StatelessWidget {
  const _BlockedCard({required this.blocks, required this.isBusy, required this.onUnblock});

  final List<BlockedUser> blocks;
  final bool isBusy;
  final ValueChanged<BlockedUser> onUnblock;

  @override
  Widget build(BuildContext context) {
    // 바탕은 Container 가 아니라 카드 자신의 Material 이 칠한다 — 눌림 효과가 목록과 같이 움직인다(COMMON §4-2).
    return Material(
      key: blockedCardKey,
      color: AppColors.surfaceSoft,
      shape: RoundedRectangleBorder(
        // pen 모서리 12 는 라운드 토큰(sm 8 · md 14) 사이 값이다.
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final user in blocks)
            _BlockedRow(user: user, onUnblock: isBusy ? null : () => onUnblock(user)),
        ],
      ),
    );
  }
}

/// 한 줄(pen `gNyir` BlockedUserRow): 68, 여백 [0,14], 간격 12, 아래 선 hairline-soft 1(마지막 줄에도 있다).
class _BlockedRow extends StatelessWidget {
  const _BlockedRow({required this.user, required this.onUnblock});

  final BlockedUser user;

  /// null 이면 다른 해제가 가는 중이라 멈춘다.
  final VoidCallback? onUnblock;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: blockedRowKey,
      // 높이는 최소값만 — 글자를 키우면 줄이 따라 커진다(고정 높이면 조용히 잘린다).
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          _Avatar(url: user.avatarUrl),
          const SizedBox(width: AppSpacing.sm),
          // 한 줄에 들어가면 이름 칸은 왼쪽 · 해제는 오른쪽 끝(pen). 글자를 키워 안 들어가면 해제가 이름 아래로
          // 내려간다 — 날짜("2026.09.27")를 좁은 칸에 욱여넣어 숫자 중간에서 끊지 않는다.
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                _NameColumn(user: user),
                _UnblockButton(onPressed: onUnblock),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 아바타 40 원(pen `lmb79` = Avatar `eNFmA`, 채움 hairline-soft, 이니셜 꺼짐). 서버가 준 아바타가 있으면 그린다.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: blockedAvatarKey,
      width: 40,
      height: 40,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.hairlineSoft),
      clipBehavior: Clip.antiAlias,
      child: url == null ? null : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
    );
  }
}

class _NameColumn extends StatelessWidget {
  const _NameColumn({required this.user});

  final BlockedUser user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 글자를 키워 줄이 68 보다 커질 때도 위아래가 선에 붙지 않게 한다. 배율 1.0 에서는 가운데 정렬이라 보이지 않는다.
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user.nickname,
            // pen `pxrzb` 16/700, 줄높이 속성 없음 · 렌더 23.
            style: AppTypography.bodyStrong
                .copyWith(color: AppColors.ink, fontWeight: FontWeight.w700, height: 23 / 16),
          ),
          const SizedBox(height: 2),
          Text(
            '${_dateLabel(user.blockedAt)} 차단',
            // pen `jFnCW` 12 / 보통 / muted, 줄높이 속성 없음 · 렌더 17. 사유는 적지 않는다.
            style: AppTypography.caption.copyWith(color: AppColors.muted, height: 17 / 12),
          ),
        ],
      ),
    );
  }

  /// "YYYY.MM.DD" — pen `jFnCW` 예시 "2026.09.10 차단".
  static String _dateLabel(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}.${twoDigits(date.month)}.${twoDigits(date.day)}';
  }
}

/// 해제(pen `cXZfz`): 보이는 크기 50×32, 여백 [0,12], 모서리 8, primary-wash 위 14/700 primary-text.
/// 누르는 영역은 Material 버튼의 기본 탭 크기(padded)로 48 까지 넓힌다 — 보이는 칸은 그대로다.
class _UnblockButton extends StatelessWidget {
  const _UnblockButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: AppColors.primaryWash,
        foregroundColor: AppColors.primaryText,
        // pen 에 멈춘 상태가 없다 — 바탕은 그대로 두고 글자만 흐리게 한다.
        disabledBackgroundColor: AppColors.primaryWash,
        disabledForegroundColor: AppColors.disabled,
        minimumSize: const Size(50, 32),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        // pen `P28TUK` 14/700, 줄높이 속성 없음 · 렌더 20.
        textStyle: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w700, height: 20 / 14),
      ),
      child: const Text('해제'),
    );
  }
}

/// 연락처 차단 안내(pen `pMN94`): primary-wash, 모서리 12, 여백 14, 14 / body / 1.5.
class _ContactNotice extends StatelessWidget {
  const _ContactNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '연락처로 차단한 지인은 여기가 아니라 설정 > 연락처 차단에서 관리해요.',
        style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 1.5),
      ),
    );
  }
}

/// 빈 상태(pen `KLSeQ` → Empty `TVc8b` 인스턴스 `RuUae`): 여백 [48,24], 가운데. 마스코트 120 → 24 → 제목 → 8 → 설명.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _listPadding,
        child: ConstrainedBox(
          // 목록 칸 높이만큼 채워 가운데에 둔다. 글자를 키워 넘치면 스크롤한다.
          constraints: BoxConstraints(minHeight: constraints.maxHeight - _listPadding.vertical),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/mascot-female.png', width: 120, height: 120),
                  // pen 간격 8 + 빈 사각형 8 + 간격 8.
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '아직 차단한 상대가 없어요',
                    textAlign: TextAlign.center,
                    // pen `ZBzIg` 17/600, 줄높이 속성 없음 · 렌더 25.
                    style: AppTypography.subtitle.copyWith(color: AppColors.ink, height: 25 / 17),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '신고하거나 차단한 상대가 있으면\n여기에 모여요.',
                    textAlign: TextAlign.center,
                    // pen `DFs55` 14 / 보통 / muted / 1.55.
                    style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 읽기 실패. pen 에 없는 상태 — 14c 와 같은 회색 문구에 "다시 시도" 를 붙인다.
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
