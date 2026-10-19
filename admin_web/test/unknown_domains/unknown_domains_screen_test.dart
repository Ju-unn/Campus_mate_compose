import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/stats_fakes.dart';

/// A6 미등록 학교 메일(pen mGKkm, 1440×900 — 값표 w4_pen_values + PNG A6 측정). 읽기 전용.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<FakeStatsServer> open(WidgetTester tester, {FakeStatsServer? server}) async {
    final fake = server ?? FakeStatsServer();
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: fake.api(), initialPath: '/unknown-domains');
    return fake;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;

  testWidgets('TopBar "미등록 학교 메일" · 표 (272,96) 1136 × (44 + 52 × 3), 머리 글자 x 288 · 588 · 728', (tester) async {
    await open(tester);

    expect(find.text('미등록 학교 메일'), findsNWidgets(2)); // 메뉴 + TopBar
    expect(tester.getRect(key('domain-table')), const Rect.fromLTWH(272, 96, 1136, 44 + 52 * 3));
    expect([for (final head in ['메일 도메인', '시도 횟수', '마지막 시도']) tester.getTopLeft(find.text(head)).dx], [288, 588, 728]);
  });

  testWidgets('줄: 도메인 · "12회" · 마지막 시도(한국 시각 "2026-10-18 13:40"), 서버가 준 많은 순 그대로', (tester) async {
    await open(tester);

    expect(find.text('example-univ.ac.kr'), findsOneWidget);
    expect(find.text('12회'), findsOneWidget);
    expect(find.text('2026-10-18 13:40'), findsOneWidget);
    final ys = [for (final d in ['example-univ.ac.kr', 'sample-college.ac.kr', 'demo-univ.ac.kr']) tester.getTopLeft(find.text(d)).dy];
    for (final (i, y) in ys.indexed) {
      expect(y, closeTo(96 + 44 + 52 * i + 15.5, 1));
    }
    expect(find.text('7회'), findsOneWidget);
    expect(find.text('3회'), findsOneWidget);
  });

  testWidgets('표 아래 24: 안내 "많은 순으로 보여요. 읽기 전용이에요." 12 muted', (tester) async {
    await open(tester);

    final hint = find.text('많은 순으로 보여요. 읽기 전용이에요.');
    expect(tester.getTopLeft(hint), const Offset(272, 96 + 200 + 24));
    expect((styleOf(tester, hint).fontSize, styleOf(tester, hint).color), (12, AdminColors.muted));
  });

  testWidgets('줄은 눌리지 않는다(읽기 전용) — GET 만 보낸다', (tester) async {
    final server = await open(tester);

    expect(tester.widget<Text>(find.text('12회')).data, '12회');
    expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
    expect(server.to('/admin/unknown-domains'), hasLength(1));
  });

  testWidgets('비면 "미등록 학교 메일 시도가 없어요"(빈 목록 틀)', (tester) async {
    await open(tester, server: FakeStatsServer()..domains = []);

    expect(find.text('미등록 학교 메일 시도가 없어요'), findsOneWidget);
    expect(key('domain-table'), findsNothing);
  });

  testWidgets('받는 중 안내 → 못 받으면 오류 틀 + [다시 시도]', (tester) async {
    final server = FakeStatsServer()..domainsFailure = 500;
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/unknown-domains', settle: false);
    await tester.pump();
    expect(find.text('미등록 학교 메일을 불러오고 있어요'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('미등록 학교 메일을 불러오지 못했어요'), findsOneWidget);
    server.domainsFailure = null;
    await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('example-univ.ac.kr'), findsOneWidget);
  });
}
