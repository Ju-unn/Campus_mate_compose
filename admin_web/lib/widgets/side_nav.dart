import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// pen Web/SideNav(보드 UUkLx · A2 PNG): 폭 240, 흰 바탕, 오른쪽 web-hairline 1.
/// 로고 묶음(왼쪽 28 · 위 24) 아래 24 띄워 메뉴(좌우 16, 항목 44 · 간격 4).
class SideNav extends StatelessWidget {
  const SideNav({super.key, required this.selected, required this.onSelect});

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AdminSizes.sideNavWidth,
      color: AdminColors.surface,
      // 선을 앞에 그려 메뉴 폭(208)이 선 두께만큼 줄지 않게 한다 — pen 은 선이 자리를 차지하지 않는다.
      foregroundDecoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AdminColors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Logo(),
          const SizedBox(height: AdminSpacing.sideNavHeaderGap),
          for (final section in AdminSection.values)
            Padding(
              padding: const EdgeInsets.fromLTRB(AdminSpacing.md, 0, AdminSpacing.md, AdminSpacing.xxs),
              child: _NavItem(
                key: ValueKey('nav-${section.name}'),
                section: section,
                selected: section == selected,
                onTap: () => onSelect(section),
              ),
            ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, AdminSpacing.lg, AdminSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 로고 글자는 줄 높이 1.5 로 보인다(PNG 측정 — 첫 메뉴가 y 96 에 온다)
          Text(
            'CampusMate',
            maxLines: 1,
            softWrap: false,
            style: AdminTypography.lg.copyWith(height: 1.5, color: AdminColors.primary),
          ),
          Text('관리자', maxLines: 1, style: AdminTypography.xs.copyWith(color: AdminColors.muted)),
        ],
      ),
    );
  }
}

/// 하루에도 수십 번 누르는 곳이라 움직임은 없다(물결 없음). pen 에 없는 상태는 웹 토큰 안에서 정했다:
/// 올림 web-ink 4% 덧칠 · 누름 8% · 키보드 초점 web-ink 2 테두리(대장 보고표로 pen 역반영).
class _NavItem extends StatefulWidget {
  const _NavItem({super.key, required this.section, required this.selected, required this.onTap});

  final AdminSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  // 마우스로 눌러서는 초점이 오지 않는다 — 초점은 키보드(Tab)로만 온다.
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final selected = widget.selected;
    final foreground = selected ? AdminColors.primaryText : AdminColors.body;
    final radius = BorderRadius.circular(AdminRadius.sm);
    return Semantics(
      button: true,
      selected: selected,
      // 바탕은 이 칸의 Material 이 칠한다 — 눌림 효과가 칸 밖(셸 Scaffold)에 그려지지 않게(COMMON §4-2).
      child: Material(
        color: selected ? AdminColors.primaryWash : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: _focused ? const BorderSide(color: AdminColors.ink, width: 2) : BorderSide.none,
        ),
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (focused) => setState(() => _focused = focused),
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          hoverColor: AdminColors.ink.withValues(alpha: 0.04),
          highlightColor: AdminColors.ink.withValues(alpha: 0.08),
          focusColor: Colors.transparent,
          child: SizedBox(
            height: AdminSizes.control,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.sm),
              child: Row(
                children: [
                  Icon(section.icon, size: AdminSizes.navIcon, color: selected ? foreground : AdminColors.muted),
                  const SizedBox(width: AdminSpacing.sm),
                  Text(section.label, style: AdminTypography.smStrong.copyWith(color: foreground)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
