import 'package:campus_mate_admin/home/home_item.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 운영 상태판(pen aB4TU → r6YXXx): 폭 520(부모가 정한다) · web-surface · web-outline 1 · 모서리 14 · 안쪽 24, 세로 간격 4 —
/// 제목 16/700 → 줄 다섯(높이 44, 아래 web-hairline 1) → 안내 12 muted. 판정은 서버 그대로(정상 · 경고 · 위험 · 해당 없음).
/// 정상 줄 = circle-check 18 + 14 body + 배지 "정상"(success), 이상 줄 = triangle-alert 18(경고 warning · 위험 danger) + 14/600 ink + 배지 "n개" 등.
class HealthPanel extends StatelessWidget {
  const HealthPanel({super.key, required this.health});

  final HealthReport health;

  /// 서버가 볼 수 없는 점검 — 환불 배치는 DB 흔적이 없다
  static const String _refundBatch = 'refund_batch';

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    final rows = [for (final item in health.items) if (healthLabel(item.key) != null) item];
    final children = <Widget>[
      Semantics(
        header: true,
        child: Text('운영 상태판', style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
      ),
      for (final item in rows) _HealthRow(item: item),
      if (health.unobservable.contains(_refundBatch))
        Text('환불 배치는 DB 흔적이 없어 여기서 볼 수 없어요(로그에서 확인).', style: AdminTypography.xs.copyWith(color: AdminColors.muted)),
    ];
    return Container(
      key: const ValueKey('health-card'),
      padding: const EdgeInsets.all(AdminSpacing.lg),
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[if (i > 0) const SizedBox(height: AdminSpacing.xxs), child],
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.item});

  final HealthItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor, badge, tone, strong) = switch (item.status) {
      'ok' => (LucideIcons.circleCheck, AdminColors.success, '정상', StatusTone.success, false),
      'warn' => (LucideIcons.triangleAlert, AdminColors.warning, healthCountLabel(item.key, item.count), StatusTone.warning, true),
      'alert' => (LucideIcons.triangleAlert, AdminColors.danger, healthCountLabel(item.key, item.count), StatusTone.danger, true),
      // 카드 줄 "지금은 점검 대상 아님"(지급 요일 아님 · 시각 전 · 받을 사람 없음) — pen 에 없는 상태라 정상 모양에 중립 배지
      'na' => (LucideIcons.circleCheck, AdminColors.muted, '해당 없음', StatusTone.neutral, false),
      // 모르는 상태는 안심 모양(check)으로 그리지 않는다 — 경고 모양 + 중립 색
      _ => (LucideIcons.triangleAlert, AdminColors.muted, '확인 안 됨', StatusTone.neutral, false),
    };
    return Container(
      key: ValueKey('health-row-${item.key}'),
      // 높이는 pen 44 가 최소 — 글자를 키워 문구가 줄을 바꾸면 줄이 늘어난다(고정하면 아래 글자가 조용히 잘린다)
      constraints: const BoxConstraints(minHeight: 44),
      // 선은 앞에 그려 줄 44 안의 가운데 정렬을 밀지 않는다(SideNav · TopBar 와 같은 이유)
      foregroundDecoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AdminColors.hairline))),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, size: 18, color: iconColor)),
          const SizedBox(width: AdminSpacing.sm),
          Expanded(
            child: Text(
              healthLabel(item.key)!,
              style: strong ? AdminTypography.smStrong.copyWith(color: AdminColors.ink) : AdminTypography.sm.copyWith(color: AdminColors.body),
            ),
          ),
          StatusBadge(badge, tone: tone),
        ],
      ),
    );
  }
}
