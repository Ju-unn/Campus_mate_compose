import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_ui_state.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 화면 15 지인 리뷰 칸(pen `Cux1p`, 간격 12): 헤더 "지인 리뷰"(`p7FSo`, SectionHeader `Ymhdq` — 오른쪽 꺼짐) →
/// 분홍 줄 "친구들이 본 나"(`o9BA0`) → 20c · 흰 줄 "내가 쓴 리뷰"(`tStBN`) → 20e.
/// 개수는 20c · 20e 와 같은 목록 뷰모델을 읽는다 — 20e 에서 지우면 돌아왔을 때 개수가 이미 줄어 있다.
class MyFriendReviewsSection extends ConsumerWidget {
  const MyFriendReviewsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final received = ref.watch(
      friendReviewListViewModelProvider((source: FriendReviewListSource.received, profileId: null)),
    );
    final written = ref.watch(
      friendReviewListViewModelProvider((source: FriendReviewListSource.written, profileId: null)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '지인 리뷰',
          // pen mHDrn 17/700 #222222, 줄높이 속성 없음 · 렌더 25(subtitle 토큰은 600).
          style: AppTypography.subtitle.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700, height: 25 / 17),
        ),
        const SizedBox(height: AppSpacing.sm),
        ProfileEntryRow(
          emphasis: true,
          icon: AppIcons.heartHandshake,
          title: '친구들이 본 나',
          note: _count('받은 리뷰', received),
          onTap: () => context.push(AppRoutes.friendReviews),
        ),
        const SizedBox(height: AppSpacing.sm),
        ProfileEntryRow(
          icon: AppIcons.messageSquareText,
          title: '내가 쓴 리뷰',
          note: _count('쓴 리뷰', written),
          onTap: () => context.push(AppRoutes.friendReviewsWritten),
        ),
      ],
    );
  }

  /// 읽는 중 · 실패는 pen 에 없다 — 노트를 비워 제목만 보인다(대장 결정 가, 줄 높이 84 그대로).
  static String _count(String label, FriendReviewListUiState state) =>
      state.isLoading || state.errorMessage != null ? '' : '$label ${state.reviews.length}개';
}
