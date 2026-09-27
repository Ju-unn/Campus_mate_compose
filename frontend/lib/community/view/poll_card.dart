import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 찬성 O 버튼 파랑(pen `VhiAe`, DESIGN §8.11). 토큰표 밖 값이다. 색 뜻 결정 대기(계획서 "결정 대기").
const Color _agreeBlue = Color(0xFF2D96DE);

/// 카드 그림자(pen `RpRBi` #00000014 (0,1) blur 8). AppElevation 토큰과 값이 달라 여기 둔다.
const List<BoxShadow> _cardShadow = [BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 8)];

/// `poll-card`(pen 마스터 `RpRBi`). 15d 목록과 17c 상세가 같이 쓴다.
class PollCard extends StatelessWidget {
  const PollCard({
    required this.poll,
    required this.now,
    required this.isVoting,
    required this.onVote,
    this.onOpen,
    this.onMore,
    super.key,
  });

  final Poll poll;
  final DateTime now;

  /// 응답을 기다리는 중이면 버튼을 끈다 — 되돌릴 수 없는 투표가 두 번 가지 않게.
  final bool isVoting;
  final void Function(PollChoice choice) onVote;

  /// 17c 로 가는 줄. 상세 화면 안에서는 null 이라 줄이 없고 질문도 전부 보인다.
  final VoidCallback? onOpen;

  /// 내 글에만 준다(… 메뉴, 사용자 결정 2).
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final inList = onOpen != null;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
    // 색 · 그림자는 바깥 DecoratedBox, 눌림 효과는 안쪽 투명 Material 이 받는다 — InkWell 의 가장 가까운
    // Material 이 카드 자신이라 스크롤해도 효과가 카드와 같이 움직인다(COMMON §4-2).
    return DecoratedBox(
      decoration: ShapeDecoration(color: AppColors.canvas, shape: shape, shadows: _cardShadow),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          // 목록 카드의 아래 안쪽 16 은 "자세히 보기" 누르는 영역이 품는다(_OpenRow).
          padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, inList ? 0 : AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(poll: poll, now: now, onMore: onMore),
              const SizedBox(height: AppSpacing.sm),
              Text(
                poll.question,
                // pen `b5raym` 16/700 lh1.35. 목록에서는 2줄(DESIGN §8.11).
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, height: 1.35, color: AppColors.ink),
                maxLines: inList ? 2 : null,
                overflow: inList ? TextOverflow.ellipsis : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (poll.myChoice == null)
                _BeforeVote(poll: poll, enabled: !isVoting, onVote: onVote)
              else
                _Result(poll: poll),
              if (inList) _OpenRow(onOpen: onOpen!),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.poll, required this.now, required this.onMore});

  final Poll poll;
  final DateTime now;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // pen `LHkpo` · `MpYr6`: #F2F2F2 pill, [3,10], 11/600 #3F3F3F. 글자는 줄 높이 속성 없음, 렌더 16 → 칩 22.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: AppColors.surfaceStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text('익명', style: AppTypography.badge.copyWith(color: AppColors.body, height: 16 / 11)),
        ),
        const SizedBox(width: AppSpacing.xs),
        // pen `G85OOq` 은 11/500 — 11px 은 뱃지만이라 12 로 올린다(대장 예외).
        Flexible(
          child: Text(
            relativeTimeLabel(poll.createdAt, now),
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted),
          ),
        ),
        // 신고 flag(`z7tzx`)는 안전 PR 6 뒤에 붙인다. "…" 는 pen `mc9mW`(터치 48 · ellipsis 20 muted) — 오른쪽 끝이
        // 아니라 시각 바로 오른쪽(머리줄 간격 8)이고, 켜지면 머리줄이 48.
        if (onMore != null) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: '더보기',
            icon: const Icon(AppIcons.ellipsis, size: 20, color: AppColors.muted),
            onPressed: onMore,
          ),
        ],
      ],
    );
  }
}

class _BeforeVote extends StatelessWidget {
  const _BeforeVote({required this.poll, required this.enabled, required this.onVote});

  final Poll poll;
  final bool enabled;
  final void Function(PollChoice choice) onVote;

  @override
  Widget build(BuildContext context) {
    VoidCallback? tap(PollChoice choice) => enabled ? () => onVote(choice) : null;
    final buttons = poll.usesDefaultLabels
        ? [
            _IconVote(icon: AppIcons.circle, label: poll.optionA, color: _agreeBlue, onPressed: tap(PollChoice.a)),
            _IconVote(icon: AppIcons.x, label: poll.optionB, color: AppColors.primary, onPressed: tap(PollChoice.b)),
          ]
        : [
            _TextVote(label: poll.optionA, onPressed: tap(PollChoice.a)),
            _TextVote(label: poll.optionB, onPressed: tap(PollChoice.b)),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: buttons[0]),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: buttons[1]),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // 투표 전에도 결과를 보인다(사용자 결정 4 · 4-1). pen `R2ZIGG` 12/400 lh1.4 muted 가운데, 버튼 줄 아래 12.
        Text(
          poll.total == 0
              // 아무도 안 눌렀으면 "0%" 두 개 대신 참여자 수만 — 0 · 0 은 결과처럼 읽힌다.
              ? '0명 참여'
              : '${poll.optionA} ${poll.aPercent}% · ${poll.optionB} ${poll.bPercent}% · ${poll.total}명 참여',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// 글자 없는 O · X 버튼(pen `VhiAe` · `mUsfX` 72 높이, radius 8, 아이콘 34 흰색).
/// 화면 읽기는 아이콘의 semanticLabel("찬성" · "반대")로 읽는다.
class _IconVote extends StatelessWidget {
  const _IconVote({required this.icon, required this.label, required this.color, required this.onPressed});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppColors.onPrimary,
        minimumSize: const Size.fromHeight(72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      child: Icon(icon, size: 34, semanticLabel: label),
    );
  }
}

/// 직접 적은 선택지 버튼(pen `ojrC5` · `ALBe4` · `OJ4rJ`, 15d-4): button-secondary 값(#E5E5E5 · #222 18/700 · 56 · radius 16).
/// AppButton 을 쓰지 않는 이유 — 높이가 56 으로 고정이라 글자를 키우면 라벨이 두 줄로 꺾여 조용히 잘린다.
/// 여기서는 한 줄로 두고 칸보다 길면 줄여서 맞춘다(한 칸 폭 144, 라벨 6자).
class _TextVote extends StatelessWidget {
  const _TextVote({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryDisabled,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.primaryDisabled,
        disabledForegroundColor: AppColors.disabled,
        minimumSize: const Size.fromHeight(56),
        // pen `ALBe4` = Button `HE8FZ` padding [0,20]. 20 은 간격 토큰(16 · 24) 사이 값이라 리터럴로 둔다.
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: AppTypography.label)),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.poll});

  final Poll poll;

  @override
  Widget build(BuildContext context) {
    // pen `omkNb`: 세로 · 가운데 · 간격 8.
    return Column(
      children: [
        PollDonut(poll: poll),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${poll.optionA} ${poll.aPercent}% · ${poll.optionB} ${poll.bPercent}%',
          textAlign: TextAlign.center,
          // pen `H1kGWf` 14/600 #3F3F3F, 줄 높이 속성 없음 · 렌더 20.
          style: AppTypography.labelSmall.copyWith(color: AppColors.body, height: 20 / 14),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${poll.total}명 참여',
          textAlign: TextAlign.center,
          // pen `rEJhW` 11/500 → 12/500(대장 예외).
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _OpenRow extends StatelessWidget {
  const _OpenRow({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted);
    // pen `i5ugzn`: 위 줄에서 12 · 줄 높이 17 · 카드 아래 안쪽 16 = 45. 누르는 영역은 48(대장)이라
    // 그 45 를 통째로 누르는 영역으로 쓰고 모자란 3 만 아래에 더한다 — 글자 자리는 pen 그대로, 카드는 3 길어진다.
    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
          child: Align(
            alignment: Alignment.topRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('자세히 보기', style: style),
                const SizedBox(width: 2),
                const Icon(AppIcons.chevronRight, size: 14, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
