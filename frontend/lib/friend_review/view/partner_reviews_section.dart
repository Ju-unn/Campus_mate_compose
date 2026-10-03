import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 화면 문구 — pen t3hFo(14c) · FXNL4(14d), 값표 B §4 · §5.
const _sectionTitle = '지인 리뷰'; // pen Bw7Rz
const _sheetNotice = '리뷰는 추천 코드로 연결된 지인만 남길 수 있어요. 부적절한 내용은 신고해주세요.'; // pen prY8p

/// 14c 에 보이는 카드 수(pen 2장). 더 있으면 "N개 모두 보기" → 14d. 2개 이하면 다 보여 링크가 없다(편차).
const int _visibleCount = 2;

// 토큰에 없는 pen 값.
const double _sectionBottom = 13; // pen NCyUl → 카카오 카드
const double _linkGap = 2; // pen b3CQS gap
const double _minTapHeight = 44; // 대장 7 — 보이는 링크 줄은 17
const double _sheetMaxHeightFactor = 0.9; // pen 은 3장(hug 750)만 그렸다 — 많으면 화면 90% 까지(편차)

/// 테스트가 14d 손잡이 크기를 재는 데 쓴다.
const Key partnerReviewsSheetHandleKey = ValueKey('partner-reviews-sheet-handle');

({FriendReviewListSource source, String? profileId}) _about(String profileId) =>
    (source: FriendReviewListSource.about, profileId: profileId);

/// 14c 상대 프로필 카드 안 "지인 리뷰"(pen `t3hFo` = 원본 `HlGva`). 헤더 → 8 → 카드 → 8 → 카드 → 13.
/// 위 13 은 앞 칸이 이미 준다. 신고 깃발은 없다 — 서버가 받은 사람만 신고를 받는다(P2 · 대장 Q2).
class PartnerReviewsSection extends ConsumerWidget {
  const PartnerReviewsSection({required this.profileId, required this.nickname, super.key});

  final String profileId;

  /// 14d 제목 "친구들이 본 {닉네임}".
  final String nickname;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(friendReviewListViewModelProvider(_about(profileId)).select((state) => state.reviews));
    // 읽는 중 · 실패 · 0개는 자리를 차지하지 않는다(P6) — 다 읽은 뒤 14c 가 흔들리지 않게 아예 없다.
    if (reviews.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasMore = reviews.length > _visibleCount;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(moreCount: hasMore ? reviews.length : null),
            for (final review in reviews.take(_visibleCount)) ...[
              // pen bQXdk · yRH8r 8.
              const SizedBox(height: AppSpacing.xs),
              FriendReviewCard(review: review),
            ],
            const SizedBox(height: _sectionBottom),
          ],
        ),
        // "모두 보기" 누르는 영역. 보이는 줄(17)은 헤더 그대로 두고, 헤더 20 + 간격 8 + 첫 카드 위 여백 16 = 44 를
        // 덮는다(대장 7, 14c 링크 줄과 같은 "주변 칸" 방식). 위 13 은 앞 칸 몫이라 넘어갈 수 없어 아래로 넓힌다.
        // 높이는 보이지 않는 헤더 사본으로 잰다 — 글자를 키워 헤더가 44 보다 커져도 링크를 덮는다.
        if (hasMore)
          Semantics(
            button: true,
            label: '${reviews.length}개 모두 보기',
            // 눌림 효과가 스크롤과 같이 움직이게 이 칸 안에 Material 을 둔다(COMMON §4-2).
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => showPartnerReviewsSheet(context, profileId: profileId, nickname: nickname),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _minTapHeight),
                  // 높이만 재는 사본 — 낭독에서 빠진다(안 그러면 "지인 리뷰" 가 두 번 읽힌다).
                  child: ExcludeSemantics(
                    child: Visibility.maintain(
                      visible: false,
                      child: _SectionHeader(moreCount: reviews.length),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 헤더(pen `o4ZREy`): "지인 리뷰" 왼쪽 · "N개 모두 보기 ›" 오른쪽, 세로 가운데. [moreCount] 가 null 이면 링크가 없다.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.moreCount});

  final int? moreCount;

  @override
  Widget build(BuildContext context) {
    final count = moreCount;
    return Row(
      children: [
        Expanded(
          child: Text(
            _sectionTitle,
            // pen Bw7Rz 14/600 #6A6A6A, 줄높이 속성 없음 · 렌더 20.
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted, height: 20 / 14),
          ),
        ),
        if (count != null)
          // 낭독은 위 누르는 칸의 이름으로 한 번만 한다.
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count개 모두 보기',
                  // pen e1E2HG 12/600 #C4224B, 줄높이 속성 없음 · 렌더 17.
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w600,
                    height: 17 / 12,
                  ),
                ),
                const SizedBox(width: _linkGap),
                const Icon(AppIcons.chevronRight, size: 14, color: AppColors.primaryText),
              ],
            ),
          ),
      ],
    );
  }
}

/// 14d 리뷰 전체 시트를 띄운다. 섹션과 같은 목록 상태를 읽어 다시 부르지 않는다.
Future<void> showPartnerReviewsSheet(BuildContext context, {required String profileId, required String nickname}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // pen 은 시트만 그렸다(딤 없음) — 다른 시트와 같은 모달 딤 토큰을 쓴다.
    barrierColor: AppColors.scrim,
    builder: (_) => PartnerReviewsSheet(profileId: profileId, nickname: nickname),
  );
}

/// 14d 상대 지인 리뷰 전체(pen `FXNL4`): 손잡이만(닫기 없음) → 제목 · 개수 → 카드 전부(간격 12) → 안내 상자.
/// 높이는 내용만큼(hug), 화면 90% 를 넘으면 그 안에서 스크롤한다. 신고 깃발은 없다(대장 Q2).
class PartnerReviewsSheet extends ConsumerWidget {
  const PartnerReviewsSheet({required this.profileId, required this.nickname, super.key});

  final String profileId;
  final String nickname;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(friendReviewListViewModelProvider(_about(profileId)).select((state) => state.reviews));
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * _sheetMaxHeightFactor),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          // pen 그림자 #00000026 (0,-2) 16 — 그림자 토큰(AppElevation.card, 아래로 두 겹)과 다른 위쪽 한 겹이라 리터럴.
          boxShadow: AppElevation.top,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              Flexible(
                child: SingleChildScrollView(
                  // pen xWNQE 여백 [8,16,28,16]. 아래 28 은 간격 토큰(lg 24 · xl 32) 사이 값이다.
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 28),
                  child: _SheetContent(nickname: nickname, reviews: reviews),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 손잡이 영역(pen `WV87g` 위아래 12) · 손잡이 36×4 hairline r2(`w8UdMw` — 20b · 조각 6 시트와 모서리가 다르다).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          key: partnerReviewsSheetHandleKey,
          width: 36,
          height: 4,
          // pen 모서리 2 는 라운드 토큰(sm 8)보다 작은 값이다.
          decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }
}

/// pen `xWNQE` 간격 12: 머리 → 카드들 → 안내 상자.
class _SheetContent extends StatelessWidget {
  const _SheetContent({required this.nickname, required this.reviews});

  final String nickname;
  final List<FriendReview> reviews;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '친구들이 본 $nickname',
                // pen TGS1Z 20/700 #222222, 줄높이 속성 없음 · 렌더 29.
                style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20),
              ),
            ),
            Text(
              '리뷰 ${reviews.length}개',
              // pen eUxPl 14/400 #6A6A6A, 줄높이 속성 없음 · 렌더 20.
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 20 / 14),
            ),
          ],
        ),
        for (final review in reviews) ...[
          const SizedBox(height: AppSpacing.sm),
          FriendReviewCard(review: review),
        ],
        const SizedBox(height: AppSpacing.sm),
        const FriendReviewNotice(text: _sheetNotice),
      ],
    );
  }
}
