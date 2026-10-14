import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 카드 · 20b 머리의 관계 줄. DB · API 에 관계 칸이 없고 추천 · 친구 코드는 학교를 따지지 않는다 —
/// pen 의 "같은 학교 친구" 등은 예시라 고정 문구 하나로 둔다(대장 Q3, 2026-09-29). 문구는 pen iFxLX "친구"(친구 코드로 쓰기, 10-13).
const String friendReviewRelationLabel = '친구';

// 토큰에 없는 pen 값(S0MR2b).
const double _headerHeight = 48; // pen B095D 높이
const double _headerGap = 10; // pen B095D gap
const double _avatarSize = 36; // pen NUNSp · dTmnd
const double _logoSize = 28; // pen DHWAj
const EdgeInsets _chipPadding = EdgeInsets.symmetric(vertical: 6, horizontal: 10); // pen wTma6 padding [6,10]

/// 이니셜 원(pen `dTmnd` 의 폴백 글자 `e1cLm` 36 · 20b `Tb6Fe` 44). 채움 primaryWash, 닉네임 첫 글자.
/// 카드에서는 아바타가 없거나 못 불러올 때의 폴백이다(pen `S0MR2b` 개정 — 종전 "avatar_url 은 그리지 않는다(대장 09-29)" 를
/// 사용자 승인으로 뒤집었다, 10-14). 20b 머리(`Tb6Fe`)는 pen 이 아직 이니셜이라 그대로다.
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
  const FriendReviewCard({required this.review, this.onReport, this.onDelete, super.key})
      : assert(onReport == null || onDelete == null, '머리 줄 오른쪽 누름칸(pen qRvp8)은 하나다');

  final FriendReview review;

  /// 20c 만 넘긴다(P2 · 대장 Q2 09-29) — null 이면 신고 버튼(사이렌 + "신고하기", pen `qRvp8`)이 없다.
  final VoidCallback? onReport;

  /// 20e 만 넘긴다 — 신고 버튼 자리(같은 누름칸)에 휴지통. [onReport] 와 함께 쓰지 않는다.
  final VoidCallback? onDelete;

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
          _Header(
            review: review,
            action: switch ((onReport, onDelete)) {
              (final VoidCallback onPressed, _) => _ReportButton(onPressed: onPressed),
              // pen 20e E1Qfy7 trash-2(20c 신고 버튼 자리 override).
              (_, final VoidCallback onPressed) => _DeleteButton(onPressed: onPressed),
              _ => null,
            },
          ),
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

/// 머리 줄(pen `B095D`): 학교 칸 · 아바타 · 이름 칸 · 신고 버튼(20c) 또는 휴지통(20e), 간격 10, 세로 가운데.
class _Header extends StatelessWidget {
  const _Header({required this.review, required this.action});

  final FriendReview review;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final university = review.university;
    return ConstrainedBox(
      // 높이는 최소값만 — 글자를 키우면 이름 칸이 따라 늘어난다(고정이면 조용히 잘린다).
      constraints: const BoxConstraints(minHeight: _headerHeight),
      child: Row(
        children: [
          // 학교가 없으면 학교 칸 없이 아바타가 맨 앞이다(대장 09-29).
          if (university != null) ...[_SchoolBadge(university: university), const SizedBox(width: _headerGap)],
          // 닉네임은 옆 이름 글자가 읽는다 — 아바타 · 첫 글자까지 읽으면 두 번 읽힌다.
          ExcludeSemantics(child: _ReviewerAvatar(nickname: review.nickname, url: review.avatarUrl)),
          const SizedBox(width: _headerGap),
          Expanded(child: _NameColumn(nickname: review.nickname)),
          if (action case final action?) ...[const SizedBox(width: _headerGap), action],
        ],
      ),
    );
  }
}

/// 신고 버튼(pen `qRvp8` Report Review): 누름칸 48×48 · 세로 가운데 · 사이렌 22(`aXNKI`) → 간격 2 → "신고하기"(`o1niSD`).
/// 글자를 키우면 칸이 48 보다 커진다 — 고정 48 이면 글자가 조용히 잘린다. 낭독은 글자("신고하기") 하나, 사이렌 그림은 읽지 않는다.
/// 커뮤니티 투표 카드의 신고 버튼(pen `OaLnA`)과 같은 모양이다 — 공용 위젯으로 올릴지는 common/** 담당이 정한다.
class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // 눌림 효과가 카드와 같이 움직이게 버튼 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        type: MaterialType.transparency,
        child: InkResponse(
          onTap: onPressed,
          radius: 24,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon3d(AppIcon3d.siren, size: 22),
                const SizedBox(height: 2),
                Text(
                  '신고하기',
                  // pen `o1niSD` 9/600 #6E5861 lh1, 렌더 34×9. 9px 는 접근성 최소(12)보다 작지만 pen 값이라 두고,
                  // 글자 배율은 그대로 따라 커진다. 이 색은 투표 카드 신고 버튼과 이 버튼에만 있어 토큰으로 올리지 않는다.
                  style: AppTypography.caption.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: const Color(0xFF6E5861),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 휴지통 버튼(20e, pen `E1Qfy7` trash-2): 누름칸 48, 보이는 아이콘 20.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      tooltip: '리뷰 지우기',
      icon: const Icon(AppIcons.trash2, size: 20, color: AppColors.muted),
      onPressed: onPressed,
    );
  }
}

/// 학교 칸(pen `NUNSp` 36 r8 hairline 1). 로고가 있으면 흰 칸 가운데 로고 28 contain(`DHWAj`), 로고가 없는 학교거나
/// 못 불러오면 검정(surfaceInk) 칸에 학교명 첫 글자(`qwQOK`, DESIGN §13-29 폴백). 로고 주소는 학교 줄(SchoolLabel)과
/// 같은 표(universityLogosProvider — `universities.logo_path` → 공개 버킷)에서 찾는다. 오는 동안은 흰 빈칸(pen 기본 모양).
/// 학교 이름은 카드 어디에도 글자로 없어 이 칸이 학교 이름으로 읽힌다(첫 글자 · 로고 그림은 읽지 않는다).
class _SchoolBadge extends ConsumerWidget {
  const _SchoolBadge({required this.university});

  final String university;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = _BadgeBox(
      color: AppColors.surfaceInk,
      child: Text(
        university.characters.firstOrNull ?? '',
        maxLines: 1,
        // pen qwQOK 12/700. 줄높이 1 — 가운데 정렬이라 보이는 자리는 같고 배율 2.4 에서도 상자 안이다.
        style: AppTypography.caption.copyWith(color: AppColors.onInk, fontWeight: FontWeight.w700, height: 1),
      ),
    );
    final url = ref.watch(universityLogosProvider).value?[university];
    return Semantics(
      label: university,
      excludeSemantics: true,
      child: url == null
          ? initial
          : Image.network(
              url,
              width: _logoSize,
              height: _logoSize,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              // errorBuilder 는 frameBuilder 를 거치지 않는다 — 실패하면 흰 칸 대신 검정 첫 글자 칸이 통째로 온다.
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                  _BadgeBox(color: AppColors.canvas, child: child),
              errorBuilder: (context, error, stackTrace) => initial,
            ),
    );
  }
}

/// 학교 칸 틀(pen `NUNSp`): 36 r8, 안쪽 hairline 1(foregroundDecoration — 테두리가 36 을 늘리지 않는다), 가운데 정렬.
/// 폴백 설명(pen context)은 채움만 #222222 로 바꾼다고 해 검정 칸에도 테두리를 둔다.
class _BadgeBox extends StatelessWidget {
  const _BadgeBox({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.sm);
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: radius),
      foregroundDecoration: BoxDecoration(border: Border.all(color: AppColors.hairline), borderRadius: radius),
      child: child,
    );
  }
}

/// 작성자 아바타(pen `dTmnd` 36 원 primaryWash clip, 안에 `f76zn` 36 cover). 아바타가 없거나 못 불러오면 닉네임
/// 첫 글자 원([FriendReviewInitial], `e1cLm`). 오는 동안은 연분홍 빈 원(pen 칸 채움)이다.
/// 주소는 서버 `avatar_url`(최신 ready 아바타의 공개 주소) — 서비스가 만든 일러스트뿐이고 실사 사진은 오지 않는다.
/// 로고와 같은 Image.network 다(errorBuilder 로 폴백이 정해지고 시험에서 실패를 재현할 수 있다).
class _ReviewerAvatar extends StatelessWidget {
  const _ReviewerAvatar({required this.nickname, required this.url});

  final String nickname;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final initial = FriendReviewInitial(
      nickname: nickname,
      size: _avatarSize,
      // pen e1cLm 14/700 #C4224B.
      style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText, fontWeight: FontWeight.w700, height: 1),
    );
    final url = this.url;
    if (url == null) return initial;
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryWash),
      child: Image.network(
        url,
        width: _avatarSize,
        height: _avatarSize,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        // 원으로 자르는 건 그림만 — 폴백 첫 글자는 자르지 않는다(배율 2.4 에서 글자 모서리가 원 밖으로 나간다).
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => ClipOval(child: child),
        errorBuilder: (context, error, stackTrace) => initial,
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
