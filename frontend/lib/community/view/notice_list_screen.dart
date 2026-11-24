import 'dart:async';

import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/empty_notice.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/common/widgets/retry_notice.dart';
import 'package:campus_mate/community/view/community_card_parts.dart';
import 'package:campus_mate/community/view/notice_row.dart';
import 'package:campus_mate/community/viewmodel/notice_list_ui_state.dart';
import 'package:campus_mate/community/viewmodel/notice_list_view_model.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 마지막 공지까지 이만큼 남으면 다음 20개를 부른다(피드 · 댓글의 이어 읽기와 같은 400).
const double _loadMoreExtent = 400;

/// 17g 공지사항 목록(pen `unXUa`) · 빈 상태(`nA4tm`). 피드 띠에서 push 로 연다.
/// 앱바(뒤로 48 + "공지사항" 20/700) → 본문 좌우 16, 공지 줄([NoticeRow]) 사이 1px 구분선 → 유리 내비(커뮤니티 선택).
/// 불러오는 중 · 실패는 pen 에 없어 피드와 같은 공용 부품(스피너 · [RetryNotice])으로 그린다(대장 판정 9).
class NoticeListScreen extends ConsumerStatefulWidget {
  const NoticeListScreen({super.key});

  @override
  ConsumerState<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends ConsumerState<NoticeListScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // 바닥에 닿기 전에 부른다 — 닿은 뒤 부르면 빈칸이 잠깐 보인다.
      if (_scroll.position.extentAfter < _loadMoreExtent) {
        unawaited(ref.read(noticeListViewModelProvider.notifier).loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noticeListViewModelProvider);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      // 유리 내비(pen `anpHX` ref `xtj0K`) 뒤로 목록이 이어진다 — 아래 여백은 본문 MediaQuery padding.bottom.
      extendBody: true,
      // pen `G969P`: 56 · 간격 4 · [0,8], 뒤로 `B8pl1` 48(arrow-left 22) + 제목 20/700 — 17c 상세 앱바와 같은 규격.
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: AppSpacing.xxs,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
          ),
        ),
        title: Text(context.l10n.communityNoticeTitle, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
      ),
      body: Builder(builder: (bodyContext) => _body(state, MediaQuery.paddingOf(bodyContext).bottom)),
      bottomNavigationBar: const GlassBottomNav(current: AppTab.community),
    );
  }

  /// [navInset] 은 유리 내비 알약 자리(알약 + 띄움 + safe area).
  Widget _body(NoticeListUiState state, double navInset) {
    final viewModel = ref.read(noticeListViewModelProvider.notifier);
    Widget aboveNav(Widget child) => Padding(padding: EdgeInsets.only(bottom: navInset), child: child);
    final failure = state.error;
    if (state.isLoading) return aboveNav(const Center(child: CircularProgressIndicator()));
    if (failure != null) return aboveNav(RetryNotice(message: context.errorText(failure), onRetry: viewModel.refresh));
    if (state.items.isEmpty) {
      // pen `iZifx` ref `TVc8b`: 마스코트 120 · 제목만(부제 · 버튼 끔), 아래 60 띄움.
      return aboveNav(Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: EmptyNotice(
          image: Image.asset('assets/images/mascot-male.webp'),
          title: context.l10n.communityNoticeEmpty,
        ),
      ));
    }
    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: ListView.separated(
        controller: _scroll,
        // 공지가 한두 개라 화면을 못 채워도 당겨서 새로 고칠 수 있게.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, navInset + AppSpacing.sm),
        itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const CommunityCardSeparator(),
        itemBuilder: (context, index) {
          if (index == state.items.length) return const Center(child: CircularProgressIndicator());
          final notice = state.items[index];
          return NoticeRow(
            key: ValueKey('notice-${notice.id}'),
            notice: notice,
            onOpen: () => context.push('${AppRoutes.communityNotices}/${notice.id}'),
          );
        },
      ),
    );
  }
}
