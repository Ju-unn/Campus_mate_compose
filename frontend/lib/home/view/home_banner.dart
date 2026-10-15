import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 홈 배너 한 줄(pen `HomeBanner`, 대장 전달 값 10-15): 328×84 · 모서리 16 · 좌우 14 · surfaceSoft 바탕,
/// 왼쪽 흰 원 44 + 아이콘 22, 제목 15/700 · 보조 12/600, 오른쪽 chevron-right 20. 배너 전체가 누름 칸이다.
///
/// 잉크는 배너 자신의 Material 에 그린다 — 홈 목록(ListView) 안에서 움직이므로 Scaffold 에 그리면 스크롤 뒤에 떠 남는다(COMMON 4-2).
/// 높이 84 는 최소 높이다 — 글자를 키우면 늘어난다(완성도 카드와 같은 규칙, DESIGN §11.2).
class HomeBanner extends StatelessWidget {
  const HomeBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 낭독기가 배너 하나로 읽는 말("CampusMate 인스타그램 열기") — 제목 · 보조 글을 따로 읽지 않는다.
  final String semanticLabel;
  final VoidCallback onTap;

  static const double _minHeight = 84;
  static const double _sidePadding = 14;
  static const double _circleSize = 44;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
              child: Row(
                children: [
                  Container(
                    width: _circleSize,
                    height: _circleSize,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle),
                    child: Icon(icon, size: 22, color: AppColors.primaryText),
                  ),
                  // 원 ↔ 글 · 글 ↔ 화살표 12 — 대장 값에 없어 완성도 카드(글 ↔ 화살표 12)와 같게 둔다(pen 확인 대상).
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _texts()),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(AppIcons.chevronRight, size: 20, color: AppColors.primaryText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 제목 15/700 #222(15 는 타입 토큰표 밖 pen 값) · 줄 상자 20 · 보조 12/600 #6A6A6A, 제목 ↔ 보조 3(대장 검토 10-15 pen 값).
  /// 제목은 한 줄이다 — 글자를 키워 모자라면 줄이지 "CampusMate" 같은 낱말을 중간에서 자르지 않는다(앱바 제목과 같은 규칙).
  /// 보조 글은 낱말 단위로 줄을 바꿔 늘어난다.
  Widget _texts() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: AppTypography.bodySmall
                .copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 20 / 15, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted)),
      ],
    );
  }
}
