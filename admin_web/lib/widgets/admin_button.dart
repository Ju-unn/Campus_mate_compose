import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_motion.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:flutter/material.dart';

/// pen Web/Button(보드 UUkLx): 주 · 보조 · 위험 · 글자 단추.
enum AdminButtonVariant { primary, secondary, danger, text }

/// 높이 44 · 모서리 8 · 좌우 20(PNG 측정) · 글자 14/600. [expand] 면 부모 폭을 채운다.
/// TextButton 이 자기 Material 을 가져 눌림 효과가 단추에 붙는다(COMMON §4-2).
///
/// 상태는 pen 보드 상태줄(Web/Button · 상태, 10-18 역반영)과 같다: 올림 web-ink 6% 덧칠 · 누름 12% 덧칠(주 단추는
/// 덧칠 없이 web-primary-pressed 바탕) · 키보드 초점 web-ink 2 테두리 · 비활성 web-surface-strong 바탕 + web-disabled 글자
/// (보조 테두리 web-outline, 글자 단추는 바탕 없음) · 요청 중 도는 아이콘 16 + 8 + 글자(색 그대로) · 물결 없음 · 색 변화 120ms.
class AdminButton extends StatelessWidget {
  const AdminButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AdminButtonVariant.primary,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AdminButtonVariant variant;

  /// 요청 중 — 글자 앞에 도는 아이콘을 두고 눌리지 않는다(색은 그대로 — 비활성처럼 보이지 않게)
  final bool loading;
  final bool expand;

  static final Color _hoverOverlay = AdminColors.ink.withValues(alpha: 0.06);
  static final Color _pressOverlay = AdminColors.ink.withValues(alpha: 0.12);
  static const BorderSide _focusRing = BorderSide(color: AdminColors.ink, width: 2);

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = _colors();
    final isPrimary = variant == AdminButtonVariant.primary;
    // loading 이면 눌리지 않지만(disabled) 비활성 색으로 바꾸지 않는다.
    final dim = !loading;
    final button = TextButton(
      onPressed: loading ? null : onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return dim ? _disabledBackground() : background;
          if (isPrimary && states.contains(WidgetState.pressed)) return AdminColors.primaryPressed;
          return background;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) && dim ? AdminColors.disabled : foreground,
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return isPrimary ? Colors.transparent : _pressOverlay;
          if (states.contains(WidgetState.hovered)) return _hoverOverlay;
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return _focusRing;
          if (border == null) return BorderSide.none;
          return BorderSide(color: states.contains(WidgetState.disabled) && dim ? AdminColors.outline : border);
        }),
        splashFactory: NoSplash.splashFactory,
        animationDuration: AdminMotion.reduced(context) ? Duration.zero : AdminMotion.press,
        minimumSize: const WidgetStatePropertyAll(Size(0, AdminSizes.control)),
        fixedSize: const WidgetStatePropertyAll(Size.fromHeight(AdminSizes.control)),
        // 데스크톱 웹은 기본 밀도가 compact(높이 -8), 휴대폰 기본은 누름 영역 48 — 둘 다 pen 44 를 바꾸므로 막는다.
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        textStyle: const WidgetStatePropertyAll(AdminTypography.smStrong),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminRadius.sm))),
      ),
      child: loading ? _Loading(label: label, color: foreground) : Text(label),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Color _disabledBackground() {
    return variant == AdminButtonVariant.text ? Colors.transparent : AdminColors.surfaceStrong;
  }

  (Color, Color, Color?) _colors() {
    return switch (variant) {
      AdminButtonVariant.primary => (AdminColors.primary, AdminColors.onPrimary, null),
      // web-outline-strong #767676 (campus-pen 재조회 10-18 확인)
      AdminButtonVariant.secondary => (AdminColors.surface, AdminColors.ink, AdminColors.outlineStrong),
      AdminButtonVariant.danger => (AdminColors.danger, AdminColors.onPrimary, null),
      AdminButtonVariant.text => (Colors.transparent, AdminColors.primaryText, null),
    };
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminLoader(color: color),
        const SizedBox(width: AdminSpacing.xs),
        Text(label),
      ],
    );
  }
}
