import 'package:campus_mate/community/model/data/notice.dart';
import 'package:campus_mate/community/view/notice_parts.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 공지 목록 한 줄(pen NoticeRow `bGQGW`, 328×103): 가로 간격 12 · 위아래 14 · 세로 가운데.
/// 왼쪽: 제목 16/600 lh1.4 ink 최대 2줄 → 6 → 날짜 "M월 D일" 12/500 muted · NEW(7일 안, 서버 값) · 말풍선 14 + 댓글 수(간격 8).
/// 오른쪽: 그림이 있는 공지만 56×56 썸네일(surface-soft · 모서리 sm) — 없으면 칸을 빼 제목이 넓어진다(값표 A4 ①).
class NoticeRow extends StatelessWidget {
  const NoticeRow({required this.notice, required this.onOpen, super.key});

  final Notice notice;
  final VoidCallback onOpen;

  /// 시험이 썸네일 자리 · 크기를 잰다.
  static const thumbnailKey = Key('notice-row-thumbnail');

  /// pen 줄 위아래 안쪽 14 · 제목과 메타 사이 6 — 간격 토큰 사이 값이라 숫자로 둔다.
  static const double _verticalPadding = 14;
  static const double _copyGap = 6;

  /// pen Thumbnail 56×56.
  static const double _thumbnailSize = 56;

  @override
  Widget build(BuildContext context) {
    final imageUrl = notice.imageUrl;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
          child: Row(
            children: [
              Expanded(child: _copy(context)),
              if (imageUrl != null) ...[const SizedBox(width: AppSpacing.sm), _thumbnail(imageUrl)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _copy(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notice.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyStrong.copyWith(height: 1.4, color: AppColors.ink),
          ),
          const SizedBox(height: _copyGap),
          _meta(context),
        ],
      );

  Widget _meta(BuildContext context) {
    final style = AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(noticeDateLabel(context, notice.createdAt), style: style),
        if (notice.isNew) const NoticeNewBadge(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.messageCircle, size: 14, color: AppColors.muted),
            const SizedBox(width: AppSpacing.xxs),
            Text('${notice.commentCount}', style: style),
          ],
        ),
      ],
    );
  }

  Widget _thumbnail(String url) => ClipRRect(
        key: thumbnailKey,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ColoredBox(
          color: AppColors.surfaceSoft,
          child: SizedBox.square(dimension: _thumbnailSize, child: NoticeImage(url: url, width: _thumbnailSize)),
        ),
      );
}
