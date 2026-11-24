import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/data/notice.dart';
import 'package:campus_mate/community/view/community_card_parts.dart';
import 'package:campus_mate/community/view/notice_parts.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 공지 상세 카드(pen NoticePost · Detail `pnMfk`, 17h `chZz8` 의 `b1yIw`): 게시물 카드와 같은 바깥 틀, 안쪽 16 · 세로 간격 14.
/// 운영자 줄(메가폰 3D 32 · "CampusMate 운영자" 14/600 · 날짜 12/500 muted) → 제목 20/600 → 그림(있을 때만, 그림 비율대로) → 본문 16/400 lh1.6.
/// **운영자 글이라 … · 신고가 없다**(대장 판정 5). 제목 · 본문은 서버 글자 그대로 — 태그 해석 · 주소 자동 열기 없음(보안 기준 21-5).
class NoticePostCard extends StatelessWidget {
  const NoticePostCard({required this.notice, super.key});

  final Notice notice;

  /// 시험이 그림 칸 크기를 잰다.
  static const imageKey = Key('notice-post-card-image');

  /// pen 카드 안 간격 14 · 운영자 줄 간격 10 — 간격 토큰 사이 값이라 숫자로 둔다.
  static const double _gap = 14;
  static const double _authorGap = 10;

  @override
  Widget build(BuildContext context) {
    final imageUrl = notice.imageUrl;
    return CommunityCardFrame(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _author(context),
          const SizedBox(height: _gap),
          Text(notice.title, style: AppTypography.title.copyWith(color: AppColors.ink)),
          if (imageUrl != null) ...[const SizedBox(height: _gap), _image(imageUrl)],
          const SizedBox(height: _gap),
          Text(notice.text, style: AppTypography.body.copyWith(color: AppColors.ink)),
        ],
      ),
    );
  }

  Widget _author(BuildContext context) => Row(
        children: [
          const Icon3d(AppIcon3d.megaphone, size: 32),
          const SizedBox(width: _authorGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.communityNoticeAuthor,
                  style: AppTypography.labelSmall.copyWith(color: AppColors.ink),
                ),
                Text(
                  noticeDateLabel(context, notice.createdAt),
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, height: 16 / 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      );

  /// pen Image Slot `c4099` surface-soft · 모서리 md. pen 은 296×166(16:9)이지만 자르지 않고 그림 비율대로 높이를 잡는다
  /// (사용자 11-25, 오는 중 · 못 받으면 16:9 빈 칸). 받은 그림을 누르면 전체 화면으로 크게 본다.
  Widget _image(String url) => ClipRRect(
        key: imageKey,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ColoredBox(
          color: AppColors.surfaceSoft,
          child: LayoutBuilder(builder: (context, box) => NoticeImage(url: url, width: box.maxWidth, whole: true)),
        ),
      );
}
