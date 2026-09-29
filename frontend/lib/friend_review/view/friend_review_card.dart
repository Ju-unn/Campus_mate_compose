import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:flutter/material.dart';

/// 카드 · 20b 머리의 관계 줄. DB · API 에 관계 칸이 없고 추천은 학교를 따지지 않는다 —
/// pen 의 "같은 학교 친구" 등은 예시라 고정 문구 하나로 둔다(대장 Q3, 2026-09-29).
const String friendReviewRelationLabel = '추천으로 연결된 친구';

// 토큰에 없는 pen 값(S0MR2b).
const double _headerHeight = 48; // pen B095D 높이
const double _headerGap = 10; // pen B095D gap
const double _avatarSize = 36; // pen NUNSp · dTmnd
const EdgeInsets _chipPadding = EdgeInsets.symmetric(vertical: 6, horizontal: 10); // pen wTma6 padding [6,10]

/// 이니셜 원(pen `dTmnd` 36 · 20b `Tb6Fe` 44). 채움 primaryWash, 닉네임 첫 글자.
/// avatar_url 은 그리지 않는다 — pen 이 이니셜이다(대장 09-29).
class FriendReviewInitial extends StatelessWidget {
  const FriendReviewInitial({required this.nickname, required this.size, required this.style, super.key});

  final String nickname;
  final double size;

  /// 글자 줄높이는 부른 쪽이 1 로 준다 — 원 가운데 정렬이라 pen lh1.5 와 보이는 자리가 같고,
  /// 배율 2.0 에서도 한 글자가 원 안에 들어가 잘리지 않는다.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryWash),
      child: Text(nickname.characters.firstOrNull ?? '', maxLines: 1, style: style),
    );
  }
}

/// 회색 안내 상자(20c `lybcp` · 14d `YkscK`): surfaceSoft r14 여백 14, info 20 primaryText, 간격 10,
/// 글 14/400 body. 20c 글 폭 270 고정은 328 폭에서 fill 과 같아 fill 로 둔다(14d 는 fill).
class FriendReviewNotice extends StatelessWidget {
  const FriendReviewNotice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          const Icon(AppIcons.info, size: 20, color: AppColors.primaryText),
          // pen 간격 10 은 간격 토큰(xs 8 · sm 12) 사이 값이다.
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              // pen OHJVi · prY8p 14/400 lh1.5, 렌더 22/줄.
              style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 22 / 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// 지인 리뷰 한 장(pen `S0MR2b`, 값표 B §3). 폭은 부모가 준다(20c · 14d 328, 14c 288).
/// 틀 #FFF r14 hairline 1, 여백 16, 간격 12, 그림자 없음. 머리 48 → 태그 → 한마디.
class FriendReviewCard extends StatelessWidget {
  const FriendReviewCard({required this.review, this.onReport, super.key});

  final FriendReview review;

  /// 20c 만 넘긴다(P2 · 대장 Q2 09-29) — null 이면 깃발이 없다.
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final comment = review.comment;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadius.md)),
      // 테두리를 decoration 에 두면 Container 가 테두리 두께만큼 여백을 더한다 — pen 여백 16 은 바깥선 기준이다.
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        // pen 높이 속성 없음(hug) — 부모가 높이를 넉넉히 줘도 내용만큼만.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(review: review, onReport: onReport),
          const SizedBox(height: AppSpacing.sm),
          // pen 은 칩 2개만 그려 줄바꿈 간격이 없다 — 3개가 넘치면 가로 간격과 같은 8 로 내린다.
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [for (final tag in review.tags) _TagChip(label: tag)],
          ),
          // 한마디가 없으면 줄도 간격도 없다. 100자라 말줄임 없이 다 보인다(pen 에 말줄임 없음).
          if (comment != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              comment,
              // pen kgCWd 14/400 #3F3F3F lh1.5, 렌더 22/줄.
              style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 22 / 14),
            ),
          ],
        ],
      ),
    );
  }
}

/// 머리 줄(pen `B095D`): 학교 배지 · 이니셜 · 이름 칸 · 신고 깃발, 간격 10, 세로 가운데.
class _Header extends StatelessWidget {
  const _Header({required this.review, required this.onReport});

  final FriendReview review;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final university = review.university;
    return ConstrainedBox(
      // 높이는 최소값만 — 글자를 키우면 이름 칸이 따라 늘어난다(고정이면 조용히 잘린다).
      constraints: const BoxConstraints(minHeight: _headerHeight),
      child: Row(
        children: [
          // 학교가 없으면 배지 없이 이니셜이 맨 앞이다(대장 09-29).
          if (university != null) ...[_SchoolBadge(university: university), const SizedBox(width: _headerGap)],
          FriendReviewInitial(
            nickname: review.nickname,
            size: _avatarSize,
            // pen e1cLm 14/700 #C4224B.
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(width: _headerGap),
          Expanded(child: _NameColumn(nickname: review.nickname)),
          if (onReport != null) ...[
            const SizedBox(width: _headerGap),
            IconButton(
              // 누름칸 48(pen qRvp8), 보이는 깃발 20.
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: '신고하기',
              icon: const Icon(AppIcons.flag, size: 20, color: AppColors.muted),
              onPressed: onReport,
            ),
          ],
        ],
      ),
    );
  }
}

/// 학교 배지(pen `NUNSp`): 36 surfaceInk r8, 학교명 첫 글자 12/700 흰색. 로고 파일이 오기 전 폴백(DESIGN §13-29).
class _SchoolBadge extends StatelessWidget {
  const _SchoolBadge({required this.university});

  final String university;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.surfaceInk, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Text(
        university.characters.firstOrNull ?? '',
        maxLines: 1,
        // pen qwQOK 12/700. 줄높이 1 — 가운데 정렬이라 보이는 자리는 같고 배율 2.0 에서도 상자 안이다.
        style: AppTypography.caption.copyWith(color: AppColors.onInk, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}

/// 이름 · 관계(pen `v4ooDN`, 간격 1).
class _NameColumn extends StatelessWidget {
  const _NameColumn({required this.nickname});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nickname,
          // pen jQizo 16/600 #222222 lh1.5, 렌더 24.
          style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 24 / 16),
        ),
        const SizedBox(height: 1),
        Text(
          friendReviewRelationLabel,
          // pen iFxLX 12/400 #6A6A6A lh1.5, 렌더 19.
          style: AppTypography.caption.copyWith(color: AppColors.muted, height: 19 / 12),
        ),
      ],
    );
  }
}

/// 태그 칩(pen `wTma6`): primaryWash r999 여백 [6,10], 테두리 없음, 12/600 primaryText.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: _chipPadding,
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        label,
        // pen vqzLE 12/600 lh1.5, 렌더 19 → 칩 31.
        style: AppTypography.caption.copyWith(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w600,
          height: 19 / 12,
        ),
      ),
    );
  }
}
