import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 설정형 구역 머리(계정 16e · 알림 설정 16d, pen `GsxGU` 등) — 14/700 muted 글자 하나, 줄높이 속성 없음이라 20/14 로 맞춘다.
/// 아래 간격 8 은 쓰는 쪽이 둔다(머리 20 + 8 = pen 28).
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.muted, height: 20 / 14),
    );
  }
}

/// 목록형 구역 머리(pen SectionHeader `Ymhdq`) — 제목 왼쪽 18/700 ink(렌더 25), [trailing] 은 오른쪽 끝 14/400 muted(렌더 20),
/// 세로 가운데. [trailing] 이 null 이면 글자를 그리지 않는다(pen `A8LX2` 꺼짐).
/// 배경 · 최소 높이 · 좌우 여백은 쓰는 쪽이 정한다.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  /// 제목 18/700 — 구역 머리 안 · 밖(프로필 관리의 글자 높이 계산)에서 같은 값을 쓴다.  subtitle 토큰 18/600 에 굵기만 700, 줄높이 속성 없음 · 렌더 25.
  static final TextStyle titleStyle =
      AppTypography.subtitle.copyWith(fontWeight: FontWeight.w700, height: 25 / 18, color: AppColors.ink);

  /// 오른쪽 글자 14/400 muted — 줄높이 속성 없음 · 렌더 20.
  static final TextStyle trailingStyle = AppTypography.bodySmall.copyWith(height: 20 / 14, color: AppColors.muted);

  @override
  Widget build(BuildContext context) {
    final note = trailing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: titleStyle),
        if (note != null) ...[
          const SizedBox(width: AppSpacing.xs),
          // 글자를 키워 한 줄에 안 들어가면 제목을 밀지 않고 오른쪽 글자가 줄을 바꾼다.
          Flexible(child: Text(note, textAlign: TextAlign.end, style: trailingStyle)),
        ],
      ],
    );
  }
}
