import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/stats_fakes.dart';

/// 사이드 메뉴 8개가 모두 실제 화면에 연결된다(자리 표시 없음). 메뉴 순서는 설계서 §8-4c.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  // 글꼴이 없으면 시험용 넓은 글자로 그려져 표 칸이 실제보다 좁아 보인다
  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<void> open(WidgetTester tester, String path, {Size size = const Size(1440, 900)}) {
    return pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: FakeStatsServer().api(), initialPath: path, size: size);
  }

  testWidgets('메뉴 순서: 홈 · 인증샷 검수 · 신고 · 매칭 · 사용자 · 결제 · 미등록 학교 메일 · 작업 기록(위에서 아래)', (tester) async {
    await open(tester, '/');

    const order = [
      AdminSection.home,
      AdminSection.heartTasks,
      AdminSection.reports,
      AdminSection.matching,
      AdminSection.users,
      AdminSection.billing,
      AdminSection.unknownDomains,
      AdminSection.actions,
    ];
    expect(AdminSection.values, order);
    final ys = [for (final section in order) tester.getTopLeft(find.byKey(ValueKey('nav-${section.name}'))).dy];
    expect(ys, [...ys]..sort());
    expect([for (final section in order) section.label], ['홈', '인증샷 검수', '신고', '매칭', '사용자', '결제', '미등록 학교 메일', '작업 기록']);
  });

  testWidgets('"자리 표시"는 더 이상 없다 — 메뉴를 하나씩 눌러도 "다음 조각에서 채움"이 나오지 않는다', (tester) async {
    await open(tester, '/', size: const Size(1440, 1400));

    for (final section in AdminSection.values) {
      await tester.tap(find.byKey(ValueKey('nav-${section.name}')));
      await tester.pumpAndSettle();
      expect(find.text('다음 조각에서 채움'), findsNothing, reason: section.label);
    }
  });

  for (final (path, title) in [('/matching', '매칭 현황'), ('/unknown-domains', '미등록 학교 메일'), ('/actions', '작업 기록'), ('/', '홈')]) {
    testWidgets('$path → TopBar "$title" · 그 화면', (tester) async {
      await open(tester, path);

      expect(find.text(title), findsWidgets);
      expect(locationOf(tester), path);
    });
  }

  testWidgets('메뉴 아래 주소(/matching/abc)도 같은 매칭 화면 — 홈으로 튕기지 않는다', (tester) async {
    await open(tester, '/matching/abc');

    expect(find.text('누가 누구랑 매칭됐나'), findsOneWidget);
  });

  testWidgets('사이드 메뉴 "매칭" → /matching, "미등록 학교 메일" → /unknown-domains, "작업 기록" → /actions', (tester) async {
    await open(tester, '/');

    await tester.tap(find.byKey(const ValueKey('nav-matching')));
    await tester.pumpAndSettle();
    expect(locationOf(tester), '/matching');
    await tester.tap(find.byKey(const ValueKey('nav-unknownDomains')));
    await tester.pumpAndSettle();
    expect(locationOf(tester), '/unknown-domains');
    await tester.tap(find.byKey(const ValueKey('nav-actions')));
    await tester.pumpAndSettle();
    expect(locationOf(tester), '/actions');
  });
}
