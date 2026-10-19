import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:flutter_test/flutter_test.dart';

/// TopBar · 탭 제목(pen A4 · A5 · A8 · A9): 신고 상세 · 사용자 · 사용자 상세 · 결제 조회 · 매칭 현황
void main() {
  test('제목: 메뉴 이름과 다른 것은 신고 아래 · 사용자 아래 · 결제', () {
    expect(AdminSection.reports.titleOf('/reports'), '신고');
    expect(AdminSection.reports.titleOf('/reports/r1'), '신고 상세');
    expect(AdminSection.users.titleOf('/users'), '사용자');
    expect(AdminSection.users.titleOf('/users/u1'), '사용자 상세');
    expect(AdminSection.billing.titleOf('/billing'), '결제 조회');
    expect(AdminSection.billing.label, '결제'); // 메뉴 글자는 그대로
    expect(AdminSection.home.titleOf('/'), '홈');
  });

  test('매칭은 TopBar 에 "매칭 현황"(pen A9), 메뉴 글자는 "매칭"', () {
    expect(AdminSection.matching.titleOf('/matching'), '매칭 현황');
    expect(AdminSection.matching.label, '매칭');
    expect(AdminSection.unknownDomains.titleOf('/unknown-domains'), '미등록 학교 메일');
    expect(AdminSection.actions.titleOf('/actions'), '작업 기록');
  });

  test('졸업생 메뉴는 TopBar 에 "졸업생 검수"(pen A10), 메뉴 글자는 "졸업생"', () {
    expect(AdminSection.graduates.titleOf('/graduates'), '졸업생 검수');
    expect(AdminSection.graduates.titleOf('/graduates/g1'), '졸업생 검수');
    expect(AdminSection.graduates.label, '졸업생');
    expect(AdminSection.ownerOf('/graduates/g1'), AdminSection.graduates);
  });

  test('사용자 · 결제 아래 주소도 그 메뉴 소속', () {
    expect(AdminSection.ownerOf('/users/8f3a'), AdminSection.users);
    expect(AdminSection.ownerOf('/billing'), AdminSection.billing);
  });
}
