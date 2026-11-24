import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/data/notice.dart';
import 'package:campus_mate/community/view/notice_parts.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 피드 맨 위 공지 띠(pen NoticeBanner `yypXr` / NEW 없음 `Xfguu`, 17 `ahtJd` 의 `YI0AM`): 328×52, 흰 · 모서리 md ·
/// 그림자 (0,1) 8, 가로 [0,14] · 간격 10 · 세로 가운데. 메가폰 3D 28 → 제목 14/600 lh1.4 ink 한 줄 → NEW → chevron 20 muted.
/// 가장 최근 공지 하나만 올린다. 누르면 공지 목록(17g)으로 간다.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({required this.notice, required this.onOpen, super.key});

  final Notice notice;
  final VoidCallback onOpen;

  /// pen 띠 높이 52 · 안쪽 14 · 간격 10 — 간격 토큰(12 · 16 · 8) 사이 값이라 숫자로 둔다.
  static const double height = 52;
  static const double _sidePadding = 14;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
    return DecoratedBox(
      decoration: ShapeDecoration(color: AppColors.canvas, shape: shape, shadows: AppElevation.homeTileLow),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
              child: Row(children: _children()),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _children() => [
        const Icon3d(AppIcon3d.megaphone, size: 28),
        const SizedBox(width: _gap),
        Expanded(
          child: Text(
            notice.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(height: 1.4, color: AppColors.ink),
          ),
        ),
        if (notice.isNew) ...[const SizedBox(width: _gap), const NoticeNewBadge()],
        const SizedBox(width: _gap),
        const Icon(AppIcons.chevronRight, size: 20, color: AppColors.muted),
      ];
}
