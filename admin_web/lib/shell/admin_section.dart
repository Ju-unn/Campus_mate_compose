import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 왼쪽 메뉴 순서(설계서 §9 + 10-18 결제 · 매칭(A9, §8-4c) 추가). 경로는 화면 주소일 뿐 서버 경로와 무관하다.
/// 아이콘은 pen SideNav(UUkLx) 의 Lucide 선 아이콘(매칭 heart-handshake — 대장 지시 10-18).
enum AdminSection {
  home('/', '홈', LucideIcons.house),
  heartTasks('/heart-tasks', '인증샷 검수', LucideIcons.image),
  reports('/reports', '신고', LucideIcons.flag),
  matching('/matching', '매칭', LucideIcons.heartHandshake),
  users('/users', '사용자', LucideIcons.users),
  billing('/billing', '결제', LucideIcons.creditCard),
  unknownDomains('/unknown-domains', '미등록 학교 메일', LucideIcons.mail),
  actions('/actions', '작업 기록', LucideIcons.clipboardList);

  const AdminSection(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;

  /// TopBar · 탭 제목. 신고 아래 주소(`/reports/{id}`)는 "신고 상세"(pen A4 상세 TopBar), 그 밖은 메뉴 이름.
  String titleOf(String path) => this == reports && path != this.path ? '신고 상세' : label;

  /// 주소가 속한 메뉴. 메뉴 경로와 같거나 그 아래(`/reports/123` → 신고)면 그 메뉴, 홈은 `/` 하나만.
  static AdminSection? ownerOf(String path) {
    for (final section in values) {
      if (section.path == path) return section;
      if (section != home && path.startsWith('${section.path}/')) return section;
    }
    return null;
  }
}
