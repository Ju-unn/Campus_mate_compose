import 'package:campus_mate/billing/task/model/data/heart_task.dart';
import 'package:campus_mate/billing/task/view/heart_task_chip.dart';
import 'package:campus_mate/billing/task/view/heart_task_pending_list.dart';
import 'package:campus_mate/billing/task/view/heart_task_text.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// 재화 하트(DESIGN §5.4 — Lucide 가 아니라 이미지). pen `l4vdk` 18.
const String _heartAsset = 'assets/images/heart-flat-vector-v3.png';

/// 반려 줄 사유 한 줄(pen ReasonRow `ydq0k`) — 테스트가 크기 · 위치를 재는 표식.
const Key heartTaskRejectLineKey = ValueKey('heart-task-reject-line');

/// pen HeartTaskRow `R99dx` — 18a 한 줄. 상태 넷: 미완료 `JQNcz` · 검수 중(마스터) · 완료 `gGX34` · 반려 `w3aZL`.
/// 쓴 횟수(1/3) · "이번 주" 는 pen 에 없어 보이지 않는다(대장 09-28).
/// 검수 중인 제출이 있으면 줄 아래에 "검수 대기" 블록이 붙는다(pen 18a `pVxvl` · `tYwTB`, 인증샷 여러 장 2026-10-19).
/// 월 한도가 여럿인 항목(단톡방)은 검수 중이어도 한도까지 이어 낸다 — 줄 문구가 "이번 달 n회 남음 / 한도 도달" 이 되고
/// 칩은 "검수 중" 대신 "제출하기"(남았으면 활성, 한도면 비활성)다. 에브리타임(월 1회)은 지금처럼 검수 중 칩.
class HeartTaskRow extends StatelessWidget {
  const HeartTaskRow({required this.task, required this.onTap, this.pendingGap = AppSpacing.xs, super.key});

  final HeartTask task;

  /// 누를 수 있는 줄(미완료 · 반려)만 준다. 검수 중 · 완료 줄은 null.
  final VoidCallback? onTap;

  /// 줄과 그 아래 대기 블록 사이 간격 — 줄 목록의 줄 사이 간격과 같다(pen 18a FreeSection gap 8, 값표 `pVxvl` · `tYwTB` 실측 ≈ 8).
  /// 하트 스토어(18)는 줄 사이가 4 라 4 를 준다.
  final double pendingGap;

  /// 검수 중에도 이어 낼 수 있는 항목의 대기 상태 — 한도가 여럿(단톡방)이고 검수 중인 제출이 있다.
  bool get _queued => task.kind.needsProof && task.limit > 1 && task.pending.isNotEmpty;

  /// 한도 도달 안내(pen `tYwTB`). 승인 수 = 쓴 횟수(검수 중 + 승인) − 검수 중.
  String? _limitNote(AppLocalizations l10n) => _queued && !task.canSubmit
      ? l10n.billingTaskLimitNote(
          limit: task.limit,
          approved: task.used - task.pending.length,
          reviewing: task.pending.length,
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final row = Container(
      // 사유 줄이 있는 반려 줄은 72(pen TW2ki 인스턴스 X4X2C · Ckrfi · Q6Olj), 없는 줄은 64.
      constraints: BoxConstraints(minHeight: _reason == null ? 64 : 72),
      decoration: BoxDecoration(
        border: Border(
          // 반려 줄은 아래 선이 투명하다(pen `w3aZL`).
          bottom: BorderSide(
            color: task.state == HeartTaskState.rejected ? Colors.transparent : AppColors.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          // pen 3D 28, 줄 안 x0 · 세로 가운데(공지 `k1Fst` · `MLkdv` d7e1q · 공유 n40Hd · 투표 x5QLa, 값표 1004).
          Icon3d(_icon, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // pen 14/600, 줄높이 속성 없음 · 렌더 20.
                    Flexible(
                      child: Text(_title(l10n), style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 20 / 14)),
                    ),
                    if (task.kind == HeartTaskKind.pollVote) ...[const SizedBox(width: 6), const _DailyBadge()],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Image.asset(_heartAsset, width: 18, height: 18, semanticLabel: l10n.commonHeart),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        _rewardText(l10n),
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
                if (_reason case final reason?) ...[
                  const SizedBox(height: 2),
                  _RejectLine(reason),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _trailing(l10n),
        ],
      ),
    );
    final onTap = this.onTap;
    // 잉크는 줄 자신에 그린다 — 목록을 밀어도 눌림 테두리가 제자리에 뜨지 않게(COMMON §4-2).
    final tappable = onTap == null ? row : Material(type: MaterialType.transparency, child: InkWell(onTap: onTap, child: row));
    if (task.pending.isEmpty) return tappable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [tappable, SizedBox(height: pendingGap), HeartTaskPendingList(pending: task.pending, note: _limitNote(l10n))],
    );
  }

  /// 반려 줄에서만, 서버가 사유를 준 때만 있다(없으면 사유 줄 없이 64 그대로).
  HeartTaskRejectReason? get _reason => task.state == HeartTaskState.rejected ? task.rejectReason : null;

  AppIcon3d get _icon => switch (task.kind) {
        HeartTaskKind.everytimePost => AppIcon3d.megaphone,
        HeartTaskKind.kakaoShare => AppIcon3d.share,
        HeartTaskKind.pollVote => AppIcon3d.vote,
      };

  String _title(AppLocalizations l10n) => switch (task.kind) {
        HeartTaskKind.everytimePost => l10n.billingTaskEverytimePost,
        HeartTaskKind.kakaoShare => l10n.billingTaskKakaoShare,
        HeartTaskKind.pollVote => l10n.billingTaskPollVote,
      };

  /// "50 · 월 1회" · "10 · 주 최대 30"(pen 글자). 하트 수 · 한도는 서버 값이다.
  String _rewardText(AppLocalizations l10n) {
    final reward = task.rewardHearts;
    final limit = task.limit;
    if (task.kind == HeartTaskKind.pollVote) return l10n.billingTaskRewardWeekly(reward: reward, max: reward * limit);
    if (!_queued) return l10n.billingTaskRewardMonthly(reward: reward, limit: limit);
    return task.canSubmit
        ? l10n.billingTaskRewardMonthlyRemaining(reward: reward, limit: limit, left: limit - task.used)
        : l10n.billingTaskRewardMonthlyLimitReached(reward: reward, limit: limit);
  }

  Widget _trailing(AppLocalizations l10n) => _queued ? _submitChip(l10n) : _stateChip(l10n);

  /// pen Action 인스턴스 "제출하기" 84×28 · 14/600 — 활성은 "인증하기"와 같은 E5E5E5 · ink, 비활성은 #F2F2F2 · #929292(값표 `pVxvl` · `tYwTB`).
  /// 줄 높이 속성이 없어 28 에서 거꾸로 잰 16(위아래 6 + 16)을 쓴다. 눌림은 줄 전체가 받는다(칩은 그림만).
  Widget _submitChip(AppLocalizations l10n) {
    final chip = HeartTaskChip(
      label: l10n.billingTaskSubmit,
      background: task.canSubmit ? AppColors.primaryDisabled : AppColors.surfaceStrong,
      foreground: task.canSubmit ? AppColors.ink : AppColors.disabled,
      minWidth: 84,
      labelStyle: AppTypography.labelSmall.copyWith(color: task.canSubmit ? AppColors.ink : AppColors.disabled, height: 16 / 14),
    );
    // 활성은 줄 전체의 탭에 합쳐 읽힌다. 비활성은 눌러지는 척하지 않게 "비활성 버튼"으로 따로 읽힌다.
    return task.canSubmit ? chip : Semantics(container: true, button: true, enabled: false, child: chip);
  }

  Widget _stateChip(AppLocalizations l10n) => switch (task.state) {
        // 과제는 "인증하기"(대장 09-28, pen 인스턴스 이름 JQNcz), 투표는 pen "참여". #E5E5E5 토큰은 primaryDisabled 하나다.
        HeartTaskState.open => HeartTaskChip(
            label: task.kind.needsProof ? l10n.billingTaskVerify : l10n.billingTaskJoin,
            background: AppColors.primaryDisabled,
            foreground: AppColors.ink,
          ),
        // pen `e2aMg` 안 3D 시계 `oq6tX` 16(값표 1004).
        HeartTaskState.reviewing => HeartTaskChip(
            leading: const Icon3d(AppIcon3d.clock, size: 16),
            label: l10n.billingTaskReviewing,
            background: AppColors.surfaceStrong,
            foreground: AppColors.muted,
          ),
        HeartTaskState.done => HeartTaskChip(
            leading: const Icon(AppIcons.check, size: 12, color: AppColors.primaryText),
            label: l10n.billingTaskDone,
            background: AppColors.primaryWash,
            foreground: AppColors.primaryText,
          ),
        HeartTaskState.rejected => Text(l10n.billingTaskResubmit, style: AppTypography.labelSmall.copyWith(color: AppColors.error)),
      };
}

/// pen ReasonRow `ydq0k` — 보상 줄 아래 2, 가로 gap 4. 아이콘 `RiCqn` lucide `triangle-alert` 12 error,
/// 글자 `QiLmA` 12/600 줄높이 1.3 error("반려 · 사유", 18b-2 의 사유와 같은 HeartTaskRejectReasonText.label).
/// 넘치면 말줄임 없이 줄바꿈(Flexible). 아이콘은 글자 첫 줄 옆에 붙는다(Row start) — 글자 확대로 두 줄이 돼도 가운데로 내려가지 않는다.
/// 위 여백 1.8 = (글자 줄 15.6 − 아이콘 12) / 2, 1.0 배에서는 pen 의 가운데 맞춤과 같다. 아이콘은 글자 없이 읽히지 않게 낭독에서 빠진다.
class _RejectLine extends StatelessWidget {
  const _RejectLine(this.reason);

  final HeartTaskRejectReason reason;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: heartTaskRejectLineKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: (12 * 1.3 - 12) / 2),
          child: Icon(AppIcons.alertTriangle, size: 12, color: AppColors.error),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            context.l10n.billingTaskRejectedLine(reason: reason.label(context.l10n)),
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.error, height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// pen "매일" 배지 `Aioxz`(투표 줄만). 글자는 "하루 1번"(사용자 결정 10-12 — 하루 첫 투표만 하트, pen 동기화 대기).
class _DailyBadge extends StatelessWidget {
  const _DailyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.surfaceStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
      // pen `klkPA` 글자 칸 16 — badge 토큰 줄높이(1.3)면 14.3 이라 알약이 18.3 으로 얇아진다.
      child: Text(
        context.l10n.billingTaskDailyBadge,
        style: AppTypography.badge.copyWith(fontWeight: FontWeight.w700, color: AppColors.muted, height: 16 / 10),
      ),
    );
  }
}
