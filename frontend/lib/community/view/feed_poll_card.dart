import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/view/vote_option.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 카드 그림자(pen `IFUWA` #00000014 (0,1) 8). AppElevation 에 같은 값이 없어 여기 둔다.
const List<BoxShadow> _cardShadow = [BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 8)];

/// VS 배지 그림자(pen `UMCB0` #00000026 (0,1) 4). 이 배지에만 있는 값이다.
const List<BoxShadow> _badgeShadow = [BoxShadow(color: Color(0x26000000), offset: Offset(0, 1), blurRadius: 4)];

/// pen 머리줄 간격 10(`yKSd4` gap) — 간격 토큰 xs(8) · sm(12) 사이 값이라 토큰으로 갈음하지 않는다.
const double _headerGap = 10;

/// pen 아래 줄 · 점수 줄의 작은 간격(`OXJyX` gap 6 · `V8FlM` gap 6). 토큰 xxs(4) · xs(8) 사이 값.
const double _smallGap = 6;

/// 쪼개짐 막대(pen `t04cX`): 높이 16 · 두 막대 사이 4 · 모서리 8(높이 절반).
const double _barHeight = 16;
const double _barGap = 4;

/// 15d 피드 카드(pen 개선안 A `IFUWA` PollCard · Feed — 17A `FBT9K` · 17A-2 `O8hjge`).
/// 17c 상세는 pen 이 그대로라 옛 [PollCard](`RpRBi`)를 쓴다.
///
/// 회색 피드 위 흰 큰 카드(모서리 24): 익명 아바타 머리줄 → 질문 18/700 → 투표 전 O/X 알약 + VS · 투표 뒤 큰 퍼센트 + 쪼개짐
/// 막대 → 구분선 → 참여자 수 · "자세히 보기". **방금 이 카드에서 투표했을 때만** 결과가 0 에서 차오른다(220ms).
/// 댓글 수 · 댓글 버튼(`G4zmKC`)은 서버 기능이 없어 넣지 않았다(사용자 결정) — 그 자리에 17c 로 가는 "자세히 보기" 가 선다.
class FeedPollCard extends StatefulWidget {
  const FeedPollCard({
    required this.poll,
    required this.now,
    required this.isVoting,
    required this.onVote,
    required this.onOpen,
    this.onMore,
    this.onReport,
    super.key,
  });

  final Poll poll;
  final DateTime now;

  /// 응답을 기다리는 중이면 버튼을 끈다 — 되돌릴 수 없는 투표가 두 번 가지 않게.
  final bool isVoting;
  final void Function(PollChoice choice) onVote;

  /// 17c 투표 상세로 간다.
  final VoidCallback onOpen;

  /// 내 글에만 준다(… 메뉴, 사용자 결정 2).
  final VoidCallback? onMore;

  /// 남의 글에만 준다(신고 버튼 `U6b2tA` = `OaLnA`). 내 글이면 신고 대신 … 가 같은 자리에 선다(`C7Bsuy`).
  final VoidCallback? onReport;

  /// 시험이 자리 · 크기를 잰다.
  static const avatarKey = Key('feed-poll-avatar');
  static const vsBadgeKey = Key('feed-poll-vs');
  static const separatorKey = Key('feed-poll-separator');
  static const myPickKey = Key('feed-poll-my-pick');
  static const agreeBarKey = Key('feed-poll-bar-a');
  static const disagreeBarKey = Key('feed-poll-bar-b');

  @override
  State<FeedPollCard> createState() => _FeedPollCardState();
}

class _FeedPollCardState extends State<FeedPollCard> {
  /// 이 카드가 보는 동안 투표가 끝났다 — 결과가 처음 그려질 때 한 번만 차오른다.
  /// 스크롤로 다시 만들어지거나 새로 고침으로 들어온 "이미 투표한 카드" 는 움직이지 않는다.
  bool _justVoted = false;

  @override
  void didUpdateWidget(FeedPollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final samePoll = oldWidget.poll.id == widget.poll.id;
    final turnedVoted = oldWidget.poll.myChoice == null && widget.poll.myChoice != null;
    _justVoted = samePoll && (_justVoted || turnedVoted);
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg));
    // 색 · 그림자는 바깥 DecoratedBox, 눌림 효과는 안쪽 투명 Material 이 받는다(COMMON §4-2).
    return DecoratedBox(
      decoration: ShapeDecoration(color: AppColors.canvas, shape: shape, shadows: _cardShadow),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          // pen 아래 줄 44 + 아래 안쪽 16 = 60 을 누름 48 + 안쪽 12 로 나눈다 — 카드 높이는 pen 그대로.
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(poll: poll, now: widget.now, onMore: widget.onMore, onReport: widget.onReport),
              const SizedBox(height: AppSpacing.sm),
              Text(
                poll.question,
                // pen `UkAVk` 18/700 lh1.4 자간 -0.18 — 목록이라 2줄 말줄임(DESIGN §8.11).
                style: AppTypography.label.copyWith(height: 1.4, color: AppColors.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (poll.myChoice == null)
                _BeforeVote(poll: poll, enabled: !widget.isVoting, onVote: widget.onVote)
              else
                _Result(poll: poll, animate: _justVoted),
              const SizedBox(height: AppSpacing.sm),
              // pen `X93Ip` Separator `CqBWB` 1 #EBEBEB.
              const ColoredBox(
                key: FeedPollCard.separatorKey,
                color: AppColors.hairlineSoft,
                child: SizedBox(height: 1),
              ),
              const SizedBox(height: AppSpacing.sm),
              _Footer(total: poll.total, onOpen: widget.onOpen),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.poll, required this.now, required this.onMore, required this.onReport});

  final Poll poll;
  final DateTime now;
  final VoidCallback? onMore;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    // pen `yKSd4`: 가로 · 간격 10 · 세로 가운데. 신고 · … 가 48 이라 머리줄이 48.
    return Row(
      children: [
        // pen `W37Xp` Avatar `eNFmA` 40(원 #FFF0F2) + 3D 프로필 `PkqpC` 24. 작성자는 익명이라 사진 · 학교가 없다.
        Container(
          key: FeedPollCard.avatarKey,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
          child: const Icon3d(AppIcon3d.userRound, size: 24),
        ),
        const SizedBox(width: _headerGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // pen `l169Bi` 14/600 ink · `zxZNL` 12/500 muted — 둘 다 줄높이 속성 없음, 렌더 19 · 16.
              Text('익명', style: AppTypography.labelSmall.copyWith(height: 19 / 14, color: AppColors.ink)),
              Text(
                relativeTimeLabel(poll.createdAt, now),
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, height: 16 / 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (onMore != null) ...[
          const SizedBox(width: _headerGap),
          // pen `C7Bsuy` MoreButton `B8pl1`(터치 48 · ellipsis 20 muted) — 신고 버튼 자리.
          IconButton(
            tooltip: '더보기',
            icon: const Icon(AppIcons.ellipsis, size: 20, color: AppColors.muted),
            onPressed: onMore,
          ),
        ] else if (onReport != null) ...[
          const SizedBox(width: _headerGap),
          PollReportButton(onPressed: onReport!),
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
    // pen `MfEEJ`(O/X) · `a7GPE`(직접 적은 선택지): 알약 56 두 칸 사이 8, 가운데 VS 배지.
    final buttons = poll.usesDefaultLabels
        ? [
            VoteOption.mark(side: VoteSide.agree, semanticLabel: poll.optionA, onPressed: tap(PollChoice.a), pill: true),
            VoteOption.mark(side: VoteSide.disagree, semanticLabel: poll.optionB, onPressed: tap(PollChoice.b), pill: true),
          ]
        : [
            VoteOption.text(side: VoteSide.agree, label: poll.optionA, onPressed: tap(PollChoice.a), pill: true),
            VoteOption.text(side: VoteSide.disagree, label: poll.optionB, onPressed: tap(PollChoice.b), pill: true),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                Expanded(child: buttons[0]),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: buttons[1]),
              ],
            ),
            // 꾸밈이라 누름 · 낭독을 가로채지 않는다(두 버튼이 이미 "찬성" · "반대" 로 읽힌다).
            const IgnorePointer(child: ExcludeSemantics(child: _VsBadge())),
          ],
        ),
        // 투표 전에도 결과를 보인다(사용자 결정 4 · 4-1). pen `IFUWA` 에는 이 줄이 없다 — 보고에 "결정 필요".
        // 참여자 수는 아래 줄로 옮겨 여기서는 비율만. 아무도 안 눌렀으면 "0%" 두 개가 결과처럼 읽혀 줄을 뺀다.
        if (poll.total > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${poll.optionA} ${poll.aPercent}% · ${poll.optionB} ${poll.bPercent}%',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}

/// pen `UMCB0`: 흰 원 32 · 그림자 · "VS" 12/700 ink(렌더 16). 글자를 키우면 원 안으로 줄여 맞춘다.
class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: FeedPollCard.vsBadgeKey,
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle, boxShadow: _badgeShadow),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'VS',
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, height: 16 / 12, color: AppColors.ink),
        ),
      ),
    );
  }
}

/// 투표 뒤 결과(pen `M3OFZ`): 점수 줄(`MyVM4`) → 12 → 쪼개짐 막대(`t04cX`).
/// [animate] 면 막대가 0 에서 차오르고 숫자가 0% 부터 올라간다(`AppMotion.standard`). 동작 줄이기면 바로 최종 값.
class _Result extends StatelessWidget {
  const _Result({required this.poll, required this.animate});

  final Poll poll;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final instant = !animate || MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      // 시작 = 끝이면 움직이지 않는다. 한 번 끝나면 숫자가 바뀌어도(새로 고침) 다시 차오르지 않는다.
      tween: Tween(begin: instant ? 1 : 0, end: 1),
      duration: AppMotion.standard,
      curve: AppMotion.standardCurve,
      builder: (context, progress, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            // pen `MyVM4` alignItems end · space_between — 두 숫자의 아래가 맞는다.
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _ScoreSide(
                  label: poll.optionA,
                  percent: poll.aPercent,
                  color: pollAgreeBlue,
                  leads: poll.aPercent >= poll.bPercent,
                  mine: poll.myChoice == PollChoice.a,
                  alignEnd: false,
                  progress: progress,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _ScoreSide(
                  label: poll.optionB,
                  percent: poll.bPercent,
                  color: AppColors.primary,
                  leads: poll.bPercent >= poll.aPercent,
                  mine: poll.myChoice == PollChoice.b,
                  alignEnd: true,
                  progress: progress,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _SplitBar(aPercent: poll.aPercent, bPercent: poll.bPercent, progress: progress),
        ],
      ),
    );
  }
}

/// 한쪽 점수(pen `o9Wv41` · `hShtY`): [점 8 · 이름 14/600 · (내 선택)] → 2 → 퍼센트.
/// 이긴 쪽 32/700 ink(`q5v9f`), 진 쪽 24 body(인스턴스 덮어쓰기 `SVRCr`), 동점이면 둘 다 32.
class _ScoreSide extends StatelessWidget {
  const _ScoreSide({
    required this.label,
    required this.percent,
    required this.color,
    required this.leads,
    required this.mine,
    required this.alignEnd,
    required this.progress,
  });

  final String label;
  final int percent;
  final Color color;
  final bool leads;
  final bool mine;
  final bool alignEnd;
  final double progress;

  static final TextStyle _lead = AppTypography.display.copyWith(height: 1.2, letterSpacing: -0.02 * 32, color: AppColors.ink);
  static final TextStyle _trail = _lead.copyWith(fontSize: 24, color: AppColors.body);

  @override
  Widget build(BuildContext context) {
    // 낭독은 움직이는 숫자가 아니라 최종 값을 읽고, 내 쪽은 색이 아니라 말로 알린다.
    return Semantics(
      label: '$label $percent%${mine ? ', 내 선택' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 글자를 키우면 칩이 다음 줄로 내려간다 — 한 줄 Row 면 넘친다.
          Wrap(
            alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: _smallGap,
            runSpacing: 2,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              // pen `E98Q4B` 14/600 ink, 줄높이 속성 없음 · 렌더 19. 6자를 크게 키우면 반쪽 폭보다 길어
              // 글자가 쪼개진다 — 투표 버튼 글자처럼 한 줄 그대로 줄여 맞춘다.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: AppTypography.labelSmall.copyWith(height: 19 / 14, color: AppColors.ink)),
              ),
              if (mine) const _MyPick(),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: Text('${(percent * progress).round()}%', style: leads ? _lead : _trail),
          ),
        ],
      ),
    );
  }
}

/// "내 선택" 칩(pen `L6cpI2` · `E2zkHi`): primary-wash 알약 [3,8] · check 12 → 4 → 12/700 primary-text(렌더 16) = 높이 22.
class _MyPick extends StatelessWidget {
  const _MyPick();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: FeedPollCard.myPickKey,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.check, size: 12, color: AppColors.primaryText),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              '내 선택',
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, height: 16 / 12, color: AppColors.primaryText),
            ),
          ),
        ],
      ),
    );
  }
}

/// 쪼개짐 막대(pen `t04cX`): 왼쪽 파랑 = (폭 − 4) × A%, 오른쪽 분홍 = (폭 − 4) × B%, 사이 4.
/// 한쪽이 0% 면 남은 쪽이 끝까지 간다 — 틈 4 가 빈 끝처럼 남지 않게. 차오를 때는 두 막대가 양 끝에서 자란다.
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.aPercent, required this.bPercent, required this.progress});

  final int aPercent;
  final int bPercent;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = aPercent == 0 || bPercent == 0 ? 0.0 : _barGap;
        final span = (constraints.maxWidth - gap) * progress / 100;
        return SizedBox(
          height: _barHeight,
          child: Stack(
            children: [
              Positioned(left: 0, top: 0, bottom: 0, width: span * aPercent, child: _bar(FeedPollCard.agreeBarKey, pollAgreeBlue)),
              Positioned(right: 0, top: 0, bottom: 0, width: span * bPercent, child: _bar(FeedPollCard.disagreeBarKey, AppColors.primary)),
            ],
          ),
        );
      },
    );
  }

  static Widget _bar(Key key, Color color) => DecoratedBox(
        key: key,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_barHeight / 2)),
      );
}

/// 아래 줄(pen `OXJyX`): 사람 16 → 6 → "N명 참여" 12/500 muted ……… "자세히 보기"(댓글 버튼 `G4zmKC` 자리).
class _Footer extends StatelessWidget {
  const _Footer({required this.total, required this.onOpen});

  final int total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final caption = AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted);
    // 양 끝에 둔다. 글자를 키워 한 줄에 못 들어가면 "자세히 보기" 가 다음 줄로 내려간다 — 한 줄 Row 면 글자가 쪼개진다.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.users, size: 16, color: AppColors.muted),
            const SizedBox(width: _smallGap),
            // pen `YfHDO` 줄높이 속성 없음, 렌더 16.
            Flexible(child: Text('$total명 참여', style: caption.copyWith(height: 16 / 12))),
          ],
        ),
        InkWell(
          onTap: onOpen,
          // 누르는 영역 48(대장), 좌우 안쪽 8 은 pen 댓글 버튼 `G4zmKC` padding [0,8].
          // 가로는 글자 폭만 쓴다(widthFactor 1) — Container(alignment:) 는 줄 끝까지 늘어나 다음 줄로 밀린다.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Align(
                widthFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('자세히 보기', style: caption.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    const Icon(AppIcons.chevronRight, size: 14, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
