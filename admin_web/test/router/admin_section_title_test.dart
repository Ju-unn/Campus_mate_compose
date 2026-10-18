import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:flutter_test/flutter_test.dart';

/// TopBar · 탭 제목(pen A4 · A5 · A8): 신고 상세 · 사용자 · 사용자 상세 · 결제 조회
void main() {
  test('제목: 메뉴 이름과 다른 것은 신고 아래 · 사용자 아래 · 결제', () {
    expect(AdminSection.reports.titleOf('/reports'), '신고');
    expect(AdminSection.reports.titleOf('/reports/r1'), '신고 상세');
    expect(AdminSection.users.titleOf('/users'), '사용자');
    expect(AdminSection.users.titleOf('/users/u1'), '사용자 상세');
    expect(AdminSection.home.titleOf('/'), '홈');
  });

  test('사용자 · 결제 아래 주소도 그 메뉴 소속', () {
    expect(AdminSection.ownerOf('/users/8f3a'), AdminSection.users);
  });
}
