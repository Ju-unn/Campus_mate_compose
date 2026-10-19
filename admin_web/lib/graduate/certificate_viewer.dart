import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/heart_tasks/proof_photo_viewer.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// pen Document Viewer(PiIgf · 값표 §6): 폭 440 · 세로 12 — 머리줄(제목 16/700 web-ink + 알약 "1장" 12/600 web-muted ·
/// web-surface-strong · pill · [4,10]) → 큰 사진 높이 380(web-surface-strong · web-outline 1 · 모서리 14, 누르면 크게 보기).
/// 값표 밖: 받는 중 · 못 받음 · 사진 없음(인증샷 A3 와 같은 틀)과 큰 사진 아래 "지난 신청"(이전 신청 이력 — 결정 · 사유 · 시각만).
/// 사진은 5분 서명 주소다 — 못 그리면 [onPhotoError] 로 알려 그 건을 한 번 다시 받는다.
class CertificateViewer extends StatelessWidget {
  const CertificateViewer({
    super.key,
    required this.detail,
    required this.onOpen,
    required this.onPhotoError,
    required this.onRetry,
  });

  final AsyncValue<GraduateDetail> detail;

  /// 사진 주소를 크게 본다
  final ValueChanged<String> onOpen;
  final PhotoErrorCallback onPhotoError;
  final VoidCallback onRetry;

  static const double photoHeight = 380;

  @override
  Widget build(BuildContext context) {
    final loaded = detail.isLoading ? null : detail.value;
    final url = loaded?.photoUrl;
    return Column(
      key: const ValueKey('certificate-viewer'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  '졸업증명서 사진',
                  style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink),
                ),
              ),
            ),
            Container(
              key: const ValueKey('certificate-count'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AdminColors.surfaceStrong, borderRadius: BorderRadius.circular(AdminRadius.pill)),
              child: Text('1장', style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
            ),
          ],
        ),
        const SizedBox(height: AdminSpacing.sm),
        TapBox(
          key: const ValueKey('certificate-photo'),
          onTap: url == null ? null : () => onOpen(url),
          cursor: SystemMouseCursors.zoomIn,
          semanticLabel: url == null ? null : '졸업증명서 크게 보기',
          color: AdminColors.surfaceStrong,
          side: const BorderSide(color: AdminColors.outline),
          radius: AdminRadius.md,
          width: double.infinity,
          height: photoHeight,
          child: _photo(url),
        ),
        if (loaded != null) ...[const SizedBox(height: AdminSpacing.sm), _History(history: loaded.history)],
      ],
    );
  }

  Widget _photo(String? url) {
    if (detail.isLoading) return const Center(child: AdminLoader(color: AdminColors.muted));
    if (detail.hasError) {
      return PhotoPlaceholder(
        icon: LucideIcons.circleAlert,
        label: '사진을 불러오지 못했어요',
        action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.text, onPressed: onRetry),
      );
    }
    const none = PhotoPlaceholder(icon: LucideIcons.imageOff, label: '사진 없음');
    if (url == null) return none;
    return ProofImage(
      url: url,
      fit: BoxFit.contain,
      onError: onPhotoError,
      loading: const Center(child: AdminLoader(color: AdminColors.muted)),
      fallback: none,
    );
  }
}

/// 같은 사람의 지난 신청(최근 순 최대 5): "반려 · 졸업증명서가 아니에요 · 2026-10-17 11:20"
class _History extends StatelessWidget {
  const _History({required this.history});

  final List<GraduateHistory> history;

  @override
  Widget build(BuildContext context) {
    final caption = AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted);
    final line = AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted);
    return Column(
      key: const ValueKey('certificate-history'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('지난 신청', style: caption),
            if (history.isEmpty) ...[const SizedBox(width: AdminSpacing.xs), Text('없어요', style: line)],
          ],
        ),
        for (final entry in history) ...[const SizedBox(height: AdminSpacing.xxs), Text(_line(entry), style: line)],
      ],
    );
  }

  static String _line(GraduateHistory entry) {
    final decided = entry.decidedAt;
    return [
      entry.status.historyLabel,
      if (entry.reason != null) entry.reason!.label,
      if (decided != null) formatSubmittedAt(decided),
    ].join(' · ');
  }
}
