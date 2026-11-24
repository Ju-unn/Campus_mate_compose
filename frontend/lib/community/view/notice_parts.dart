import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 공지 띠(`yypXr`) · 목록 줄(`bGQGW`) · 상세(`pnMfk`)가 같이 쓰는 조각(할 일 21).

/// 공지 날짜 "M월 D일"(연도 없음, 값표 21-2). 기기 시간대 기준이다.
String noticeDateLabel(BuildContext context, DateTime createdAt) =>
    context.l10n.commonDateMonthDay(month: createdAt.month, day: createdAt.day);

/// NEW 배지(pen Badge `XPRBv` 덮어쓰기): primary 채움 · 끝까지 둥근 모서리 · 안쪽 [6,10] · "NEW" 10/600 흰 글자.
/// 7일 안 공지인지는 서버가 정한다(`is_new`) — 앱 시계로 다시 재지 않는다.
class NoticeNewBadge extends StatelessWidget {
  const NoticeNewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const ShapeDecoration(color: AppColors.primary, shape: StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Text(context.l10n.communityNoticeNew, style: AppTypography.badge.copyWith(color: AppColors.onPrimary)),
      ),
    );
  }
}

/// 공지 그림 — **서버가 준 주소 그대로** 받는다(앱이 주소를 만들지 않는다). 칸을 꽉 채워 자르고, 오는 중 · 못 받으면 빈 칸(바탕색만)으로 둔다.
/// 기기 캐시(CachedNetworkImage — 채팅 목록 · 채팅 그림과 같다)에 두고, 메모리에는 [width] × 화소 배율 폭으로 줄여 푼다(썸네일 56 · 상세 296).
/// 바탕 · 모서리는 놓는 쪽(썸네일 · 상세 그림 칸)이 정한다.
class NoticeImage extends StatelessWidget {
  const NoticeImage({required this.url, required this.width, super.key});

  final String url;

  /// 화면에 그려지는 폭(논리 크기).
  final double width;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
      placeholder: (context, url) => const SizedBox.shrink(),
      errorWidget: (context, url, error) => const SizedBox.shrink(),
    );
  }
}
