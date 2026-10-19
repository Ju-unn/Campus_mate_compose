import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/gate/gate_stage.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/widgets/gate_card.dart';
import 'package:campus_mate_admin/widgets/side_nav.dart';
import 'package:campus_mate_admin/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 로그인 뒤 화면 틀: 왼쪽 SideNav, 위 TopBar, 나머지 내용(web-canvas).
/// 1440 기준 · 최소 1280 — 더 좁으면 1280 으로 그리고 가로로 밀어 본다(설계서 §9 "깨지지만 않게").
/// 브라우저 Ctrl+F 가 안 먹으니 글자는 끌어서 복사할 수 있게 한다 — TopBar(관리자 메일)와 화면마다(router 의 페이지) 따로 건다.
/// 셸 전체(Navigator 포함)에 하나만 걸면, 상세 화면(/reports/123) 밑에 깔린 목록 페이지(그려지지 않음)의 글자까지
/// 재려다 멈춘다(10-18 시험에서 확인).
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.section, required this.child, this.title});

  final AdminSection section;

  /// TopBar · 탭 제목. null 이면 메뉴 이름(상세 주소는 [AdminSection.titleOf]).
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(gateProvider).value;
    final title = this.title ?? section.label;
    final email = stage is Ready ? stage.email : '';
    final shell = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SideNav(selected: section, onSelect: (next) => context.go(next.path)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectionArea(
                child: TopBar(title: title, email: email, onSignOut: () => ref.read(adminAuthProvider).signOut()),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
    final page = Scaffold(
      backgroundColor: AdminColors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= AdminSizes.minWindowWidth) return shell;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: AdminSizes.minWindowWidth, height: constraints.maxHeight, child: shell),
          );
        },
      ),
    );
    return Title(title: '$title · $appTitle', color: AdminColors.primary, child: page);
  }
}
