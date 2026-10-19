import 'package:campus_mate/billing/model/heart_task_pending.dart';
import 'package:campus_mate/billing/view/heart_task_chip.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 제출 시각 글자. 오늘이면 pen 그대로 "오늘 14:20 제출", 다른 날은 날짜를 붙인다("10월 18일 23:59 제출" — pen 에 없는 모양).
/// 서버 시각은 UTC 로 오므로 기기 시각으로 바꿔 읽는다.
String heartTaskPendingTimeLabel(DateTime createdAt, DateTime now) {
  final at = createdAt.toLocal();
  final today = now.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = '${two(at.hour)}:${two(at.minute)}';
  final sameDay = at.year == today.year && at.month == today.month && at.day == today.day;
  return sameDay ? '오늘 $clock 제출' : '${at.month}월 ${at.day}일 $clock 제출';
}

/// 18a 항목 줄 아래 "검수 대기" 블록(pen Pending Block — 18a 대기 1건 `pVxvl` · 한도 찬 상태 `tYwTB`).
/// 폭 fill · 세로 gap 8 · padding [8,0,12,40]. 제목 12/600 muted, 줄마다 썸네일(최대 3장) · 제출 시각 · "검수중" 배지.
/// [note] 가 있으면 줄들 아래 12 muted 안내(한도 도달).
class HeartTaskPendingList extends StatelessWidget {
  const HeartTaskPendingList({required this.pending, this.note, super.key});

  final List<HeartTaskPending> pending;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final note = this.note;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, AppSpacing.xs, 0, AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // pen 제목 12/600 muted, 줄높이 속성 없음 · 토큰(caption 1.4).
          Text('검수 대기 ${pending.length}건', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted)),
          for (final item in pending) ...[
            const SizedBox(height: AppSpacing.xs),
            _PendingRow(item: item, now: now),
          ],
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(note, style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

/// 한 건: 썸네일 · 제출 시각 · 배지. 글자를 키우면 시각 글자가 썸네일 아래로 접히고 배지는 오른쪽 끝에 남는다.
/// 낭독기에는 썸네일 그림 대신 "시각, 사진 n장, 검수중" 을 한 덩어리로 읽어 준다.
class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.item, required this.now});

  final HeartTaskPending item;
  final DateTime now;

  static const String _badge = '검수중';

  @override
  Widget build(BuildContext context) {
    final time = heartTaskPendingTimeLabel(item.createdAt, now);
    return Semantics(
      container: true,
      label: '$time, 사진 ${item.photoUrls.length}장, $_badge',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [for (final url in item.photoUrls) HeartTaskPendingThumb(url: url)],
                ),
                Text(time, style: AppTypography.caption.copyWith(color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // pen SaMDZ Badge · Status — 바탕 #F2F2F2 · 글자 11/700 #6A6A6A. 아이콘은 lucide timer(값표에 크기 없음 — 12 로 둔다, 보고).
          const HeartTaskChip(
            leading: Icon(AppIcons.timer, size: 12, color: AppColors.muted),
            label: _badge,
            background: AppColors.surfaceStrong,
            foreground: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

/// 썸네일 36×36 — 바탕 #EBEBEB · 모서리 8. [url] 이 null(서버가 서명에 실패한 장)이거나 못 받으면 회색 칸으로 남는다.
/// 인증샷은 기기 디스크에 남기지 않으려고 디스크 캐시가 없는 Image.network 를 쓴다(주소는 10분짜리 서명 URL).
/// 36 칸에 원본(≤1920px)을 통째로 풀지 않게 디코딩 폭을 3배(108)로 줄인다.
class HeartTaskPendingThumb extends StatelessWidget {
  const HeartTaskPendingThumb({required this.url, super.key});

  final String? url;

  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox.square(
        dimension: size,
        child: ColoredBox(
          color: AppColors.hairlineSoft,
          child: url == null
              ? null
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: 108,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
        ),
      ),
    );
  }
}
