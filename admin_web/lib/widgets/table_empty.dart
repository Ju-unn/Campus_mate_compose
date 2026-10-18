import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/enter_motion.dart';
import 'package:flutter/material.dart';

/// pen Web/Table Empty(kSwZk · A3 빈 목록 t36bfq): 폭 가득 · 높이 240 · web-surface · web-outline 1 · 모서리 14,
/// 가운데 세로 간격 8 — 아이콘 32 → 제목 16/700(렌더 22) → 설명 14 web-muted(렌더 19).
/// 같은 틀로 목록을 받는 중(도는 아이콘 + 글) · 못 받음(오류 아이콘 + 다시 시도)도 그린다 — pen 에 없는 상태(대장 보고표).
/// [enter] 면 처음 그려질 때 관문 카드와 같은 등장(EnterMotion)을 한다 — 마지막 건을 처리해 빈 목록이 됐을 때처럼 드문 순간만.
class AdminTableEmpty extends StatelessWidget {
  const AdminTableEmpty({
    super.key,
    required this.leading,
    this.title,
    this.body,
    this.action,
    this.enter = false,
    this.alert = false,
  });

  final Widget leading;
  final String? title;
  final String? body;
  final Widget? action;
  final bool enter;

  /// 오류 틀 — 제목을 화면 읽기가 바로 알린다(오류 줄 · 토스트와 같은 live region)
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    final title = this.title;
    final body = this.body;
    final action = this.action;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        if (title != null) ...[
          const SizedBox(height: AdminSpacing.xs),
          Semantics(
            header: true,
            liveRegion: alert,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink),
            ),
          ),
        ],
        if (body != null) ...[
          const SizedBox(height: AdminSpacing.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted),
          ),
        ],
        if (action != null) ...[const SizedBox(height: AdminSpacing.md), action],
      ],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 240),
      width: double.infinity,
      padding: const EdgeInsets.all(AdminSpacing.lg),
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Center(child: enter ? EnterMotion(child: content) : content),
    );
  }
}
