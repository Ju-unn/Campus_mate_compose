import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/sent_request.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:flutter/material.dart';

/// 보낸 신청 한 줄(pen 마스터 `SentRequestRow` d6otzp, 화면 `ULllO` · `wOZst` — 값은 대장이 pen 에서 읽어 준 것).
/// 행 높이 72 · 세로 가운데 · 아바타–정보 12 · 정보(fill)–상태 12 · 정보 세로 3 · 상태 칸 세로 4 · 오른쪽 맞춤.
/// 바탕 · 좌우 여백이 없다(본문 여백 16 은 목록이 준다). 행 사이 선도 목록이 긋는다.
/// 누를 수 있는 것은 **매칭됐고 방이 있는 줄뿐**이다 — 나머지 줄에는 눌림 자체를 달지 않는다.
class SentRequestRow extends StatelessWidget {
  const SentRequestRow({required this.request, required this.onOpenChat, super.key});

  final SentRequest request;

  /// 매칭된 방을 연다. [SentRequest.opensChat] 인 줄만 부른다.
  final ValueChanged<String> onOpenChat;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      // pen 높이 72 는 배율 1.0 의 값이다 — 글자를 키우면(§11.2) 줄이 따라 커지게 최솟값으로 둔다(대화 중 행과 같다).
      constraints: const BoxConstraints(minHeight: 72),
      child: Row(
        children: [
          RowAvatar(url: request.profile.avatarUrl),
          // 아바타–정보 12 · 정보–상태 12 (pen d6otzp 의 gap, 정보 칸은 fill).
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _Info(request: request)),
          const SizedBox(width: AppSpacing.sm),
          _Status(request: request),
        ],
      ),
    );
    final matchId = request.matchId;
    if (!request.opensChat || matchId == null) {
      return content;
    }
    // 눌림 효과를 행 안의 투명 Material 이 그려야 목록과 함께 움직인다(COMMON §4-2). 투명도는 낮추지 않는다.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: () => onOpenChat(matchId), child: content),
    );
  }
}

/// 이름 · 학교 줄. 둘 다 한 줄 말줄임이다 — 상태 칸이 폭을 가져가도 줄이 늘지 않는다.
class _Info extends StatelessWidget {
  const _Info({required this.request});

  final SentRequest request;

  @override
  Widget build(BuildContext context) {
    final profile = request.profile;
    // 끝난 신청(거절 · 만료)은 이름이 muted — pen override qLy1a/k2zdE6(거절됨) · b6lP9v/k2zdE6(만료됨). 기다림 · 매칭됨은 ink.
    final finished = request.status == SentRequestStatus.rejected || request.status == SentRequestStatus.expired;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.nameWithAge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyStrong.copyWith(color: finished ? AppColors.muted : AppColors.ink),
        ),
        // 이름 · 학교 줄 세로 gap 3 은 간격 토큰에 없는 pen 값이다.
        const SizedBox(height: 3),
        SchoolLabel(
          profile.university ?? '',
          text: profile.schoolLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// 오른쪽 상태 칸: 칩, 매칭됨이면 그 옆 chevron, 만료됨이면 그 아래 안내 한 줄.
class _Status extends StatelessWidget {
  const _Status({required this.request});

  final SentRequest request;

  @override
  Widget build(BuildContext context) {
    final chip = _StatusChip(request: request);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (request.opensChat)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chip,
              const SizedBox(width: AppSpacing.xxs),
              const Icon(AppIcons.chevronRight, size: 20, color: AppColors.primaryText),
            ],
          )
        else
          chip,
        if (request.status == SentRequestStatus.expired) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '응답이 없었어요',
            textAlign: TextAlign.end,
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}

/// 상태 칩. 폭은 글자에 맞춘다 — 배지(Badge · Status)의 폭 72 고정을 쓰지 않는다.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.request});

  final SentRequest request;

  @override
  Widget build(BuildContext context) {
    final matched = request.status == SentRequestStatus.matched;
    final foreground = matched ? AppColors.primaryText : AppColors.muted;
    final (icon, label) = switch (request.status) {
      SentRequestStatus.waiting => (AppIcons.timer, _waitingLabel(request.daysLeft)),
      SentRequestStatus.matched => (AppIcons.messageCircle, '매칭됨'),
      SentRequestStatus.rejected => (AppIcons.x, '거절됨'),
      SentRequestStatus.expired => (AppIcons.timerOff, '만료됨'),
    };
    return Container(
      // pen 높이 28 은 배율 1.0 의 값이다(글자 12 × 1.25 = 15 + 위아래 6 = 27 이라 28 로 채우고 가운데 둔다) — 글자를 키우면 칩이 따라 커진다.
      // 좌우 10 · 위아래 6 은 간격 토큰에 없는 pen 값이다.
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: matched ? AppColors.primaryWash : AppColors.surfaceStrong,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Center(
        widthFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: foreground),
            // 아이콘–글자 4 (pen d6otzp).
            const SizedBox(width: AppSpacing.xxs),
            // 글자 12 / 700 / 줄높이 1.25 (pen d6otzp, 대장 결정 10-13). 12 는 caption 토큰의 크기다.
            Text(
              label,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, height: 1.25, color: foreground),
            ),
          ],
        ),
      ),
    );
  }

  /// 서버 days_left 는 남은 시간의 올림(최소 1)이라 1 이면 24시간 이하다 — "1일 남음" 대신 "오늘 마감".
  /// 앱이 기기 시계로 다시 재지 않는다(대장 정정 10-13). 기다리는 중인데 값이 빠졌으면 최솟값 1 로 본다.
  static String _waitingLabel(int? daysLeft) {
    final days = daysLeft ?? 1;
    return days <= 1 ? '오늘 마감' : '$days일 남음';
  }
}
