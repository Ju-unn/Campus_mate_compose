import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// pen Web/Select(MuZJ5 · A9 GjfjR): 200×36 · 좌우 12 · web-surface · web-outline-strong 1 · 모서리 8, 현재 글자 14 web-ink + chevron-down 18 web-muted.
/// 누르면 바로 아래 4 에 펼친다 — 폭 200 · 항목 36 · 모서리 8 · web-outline-strong 1 · 높이는 320 에서 끊고 스크롤(펼친 모양은 pen 에 없어
/// 반려 사유 메뉴(krcn9)와 같은 결로 정했다). 고르면 닫히고, Esc · 바깥 누름으로도 닫힌다. 항목 키는 `${key}-option-N`, 메뉴 키는 `${key}-menu`.
class AdminSelect<T> extends StatefulWidget {
  const AdminSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.boxWidth = width,
    this.boxHeight = height,
  });

  static const double width = 200;
  static const double height = 36;
  static const double itemHeight = 36;
  static const double maxMenuHeight = 320;

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String semanticLabel;

  /// 칸 크기. 기본은 A9 의 200×36, 졸업생 검수(A10 MuZJ5)는 카드 폭 가득(280) × 44 — 펼친 메뉴 폭도 같이 따라간다.
  final double boxWidth;
  final double boxHeight;

  @override
  State<AdminSelect<T>> createState() => _AdminSelectState<T>();
}

class _AdminSelectState<T> extends State<AdminSelect<T>> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final Object _group = Object();

  bool get _open => _portal.isShowing;

  void _toggle() {
    setState(() => _open ? _portal.hide() : _portal.show());
  }

  void _close() {
    if (_open) setState(_portal.hide);
  }

  @override
  Widget build(BuildContext context) {
    final base = (widget.key is ValueKey<String>) ? (widget.key! as ValueKey<String>).value : null;
    // 옵션이 아직 없거나(받는 중) 값이 목록에 없으면 첫 항목 글자("전체 학교")
    final current = widget.options.where((o) => o.$1 == widget.value).map((o) => o.$2).firstOrNull ?? widget.options.firstOrNull?.$2 ?? '';
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Align(
            alignment: Alignment.topLeft,
            child: TapRegion(
              groupId: _group,
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
                child: Focus(autofocus: true, child: _menu(base)),
              ),
            ),
          ),
        ),
        child: TapRegion(
          groupId: _group,
          onTapOutside: (_) => _close(),
          child: Semantics(
            expanded: _open,
            child: TapBox(
              onTap: _toggle,
              semanticLabel: '${widget.semanticLabel}: $current',
              width: widget.boxWidth,
              height: widget.boxHeight,
              color: AdminColors.surface,
              side: const BorderSide(color: AdminColors.outlineStrong),
              padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(current, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.ink)),
                  ),
                  const SizedBox(width: AdminSpacing.xs),
                  const Icon(LucideIcons.chevronDown, size: 18, color: AdminColors.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu(String? base) {
    return Material(
      key: base == null ? null : ValueKey('$base-menu'),
      color: AdminColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminRadius.sm),
        side: const BorderSide(color: AdminColors.outlineStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: widget.boxWidth,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: AdminSelect.maxMenuHeight),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final (i, option) in widget.options.indexed)
                TapBox(
                  key: base == null ? null : ValueKey('$base-option-$i'),
                  onTap: () {
                    _close();
                    widget.onChanged(option.$1);
                  },
                  selected: option.$1 == widget.value,
                  radius: 0,
                  height: AdminSelect.itemHeight,
                  padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      option.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdminTypography.sm.copyWith(
                        height: AdminTypography.smBox,
                        fontWeight: option.$1 == widget.value ? FontWeight.w600 : FontWeight.w400,
                        color: AdminColors.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
