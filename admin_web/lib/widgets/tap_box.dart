import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:flutter/material.dart';

/// 누를 수 있는 상자(칩 · 목록 줄 · 사진 · 반려 Select · 사유 줄 · 닫기). 바탕 · 테두리를 이 상자의 Material 이 칠해
/// 눌림 효과가 상자에 붙는다(COMMON §4-2 — 목록이 스크롤돼도 같이 움직인다). 테두리는 안쪽에 그려 안쪽 여백을 밀지 않는다.
///
/// pen 에 없는 상태는 SideNav 항목(W0)과 같은 값이다: 올림 [overlayColor] 4% · 누름 8% 덧칠, 물결 없음,
/// 키보드 초점이면 테두리를 [focusColor] 2 로 바꾼다. [onTap] 이 없으면 눌리지 않고 커서도 바뀌지 않는다.
class TapBox extends StatefulWidget {
  const TapBox({
    super.key,
    required this.onTap,
    required this.child,
    this.color = Colors.transparent,
    this.side = BorderSide.none,
    this.radius = AdminRadius.sm,
    this.focusColor = AdminColors.ink,
    this.overlayColor = AdminColors.ink,
    this.cursor,
    this.selected,
    this.checked,
    this.semanticLabel,
    this.focusNode,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  final VoidCallback? onTap;
  final Widget child;
  final Color color;
  final BorderSide side;
  final double radius;
  final Color focusColor;
  final Color overlayColor;
  final MouseCursor? cursor;

  /// 고를 수 있는 것(칩 · 목록 줄)은 고른 상태를 화면 읽기에 알린다. 그 밖은 null.
  final bool? selected;

  /// 체크박스(켬 · 끔)는 체크 상태로 읽힌다. 그 밖은 null.
  final bool? checked;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  State<TapBox> createState() => _TapBoxState();
}

class _TapBoxState extends State<TapBox> {
  // 마우스로 눌러서는 초점이 오지 않는다 — 초점은 키보드(Tab · 단축키)로만 온다.
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.radius),
      side: _focused ? BorderSide(color: widget.focusColor, width: 2) : widget.side,
    );
    return MergeSemantics(
      child: Semantics(
        // 체크박스는 단추가 아니라 체크 상태로 읽힌다
        button: widget.onTap != null && widget.checked == null,
        selected: widget.selected,
        checked: widget.checked,
        label: widget.semanticLabel,
        child: Material(
          color: widget.color,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            focusNode: widget.focusNode,
            onFocusChange: (focused) => setState(() => _focused = focused),
            mouseCursor: widget.onTap == null ? null : widget.cursor,
            customBorder: shape,
            splashFactory: NoSplash.splashFactory,
            hoverColor: widget.overlayColor.withValues(alpha: 0.04),
            highlightColor: widget.overlayColor.withValues(alpha: 0.08),
            focusColor: Colors.transparent,
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
