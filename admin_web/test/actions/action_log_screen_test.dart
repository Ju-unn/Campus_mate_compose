import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/stats_fakes.dart';

/// A7 작업 기록(pen RHMgk, 1440×900 — 값표 w4_pen_values + PNG A7 측정). 읽기 전용.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');
  const idA = 'a0000000-0000-4000-8000-000000000001';

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<FakeStatsServer> open(WidgetTester tester, {FakeStatsServer? server, bool settle = true}) async {
    final fake = server ?? FakeStatsServer();
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: fake.api(), initialPath: '/actions', settle: settle);
    return fake;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;

  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  group('pen 배치(RHMgk)', () {
    testWidgets('TopBar "작업 기록" · 검색칸 (272,96) 320×44 placeholder "대상 id 검색" · 표 (272,164)', (tester) async {
      await open(tester);

      expect(find.text('작업 기록'), findsNWidgets(2));
      expect(tester.getRect(key('action-search-box')), const Rect.fromLTWH(272, 96, 320, 44));
      expect(find.text('대상 id 검색'), findsOneWidget);
      expect(tester.getRect(key('action-table')), const Rect.fromLTWH(272, 164, 1136, 44 + 52 * 3));
    });

    testWidgets('머리 글자 x: 시각 288 · 관리자 468 · 작업 648 · 대상 798 · 사유 998', (tester) async {
      await open(tester);

      expect([for (final head in ['시각', '관리자', '작업', '대상', '사유']) tester.getTopLeft(find.descendant(of: key('action-table'), matching: find.text(head))).dx], [288, 468, 648, 798, 998]);
    });

    testWidgets('줄(pen): "2026-10-18 14:30" · 관리자 메일 · "인증샷 승인" · "제출 e4100000…" · "-" / "정지" · "닉네임B" · "불쾌한 사진 3건" / "하트 조정 +50" · "닉네임A" · "오류 보상"', (tester) async {
      await open(tester);

      for (final text in [
        '2026-10-18 14:30',
        '인증샷 승인',
        '제출 e4100000…',
        '2026-10-18 14:21',
        '정지',
        '닉네임B',
        '불쾌한 사진 3건',
        '2026-10-18 13:55',
        '하트 조정 +50',
        '닉네임A',
        '오류 보상',
      ]) {
        expect(find.descendant(of: key('action-table'), matching: find.text(text)), findsOneWidget, reason: text);
      }
      expect(find.descendant(of: key('action-table'), matching: find.text('admin@example.com')), findsNWidgets(3));
      expect(find.descendant(of: key('action-table'), matching: find.text('-')), findsOneWidget); // 사유 없는 줄
    });

    testWidgets('관리자 메일을 못 읽은 줄(null)은 "admin"', (tester) async {
      await open(tester, server: FakeStatsServer()..actions = [actionRow('a9', '2026-10-18T05:30:00+00:00', 'profile_note', email: null)]);

      expect(find.descendant(of: key('action-table'), matching: find.text('admin')), findsOneWidget);
    });

    testWidgets('표 아래 24: 안내 12 muted "읽기 전용이에요. 기록은 2년 보관돼요. · 최근 순 50건씩"', (tester) async {
      await open(tester);

      final hint = find.text('읽기 전용이에요. 기록은 2년 보관돼요. · 최근 순 50건씩');
      expect(tester.getTopLeft(hint), const Offset(272, 164 + 200 + 24));
      expect((styleOf(tester, hint).fontSize, styleOf(tester, hint).color), (12, AdminColors.muted));
    });

    testWidgets('IP · 바뀌기 전 값은 어디에도 그리지 않는다', (tester) async {
      await open(tester);

      expect(find.textContaining('203.0.113.9'), findsNothing);
    });
  });

  group('대상 id 검색 — UUID 모양만', () {
    testWidgets('UUID 를 넣고 엔터 → target=그 id 로 다시 받는다', (tester) async {
      final server = await open(tester);

      await submit(tester, idA);

      expect(server.to('/admin/actions').last.url.queryParameters, {'target': idA});
      expect(find.byKey(const ValueKey('action-row-a3')), findsOneWidget);
      expect(find.byKey(const ValueKey('action-row-a1')), findsNothing);
    });

    testWidgets('앞뒤 공백은 다듬어 보낸다', (tester) async {
      final server = await open(tester);

      await submit(tester, '  $idA ');

      expect(server.to('/admin/actions').last.url.queryParameters, {'target': idA});
    });

    testWidgets('UUID 모양이 아니면 요청 없이 칸 아래 오류 줄 "id 모양이 아니에요", 고치기 시작하면 사라진다', (tester) async {
      final server = await open(tester);
      final before = server.to('/admin/actions').length;

      await submit(tester, '닉네임A');

      expect(server.to('/admin/actions'), hasLength(before));
      expect(find.text('id 모양이 아니에요'), findsOneWidget);
      expect(find.byType(ErrorRow), findsOneWidget);
      // 줄은 칸 아래 8, 표는 그 아래로 밀린다
      expect(tester.getTopLeft(find.byType(ErrorRow)).dy, 96 + 44 + 8);
      await tester.enterText(find.byType(TextField), '닉네임');
      await tester.pump();
      expect(find.text('id 모양이 아니에요'), findsNothing);
    });

    testWidgets('필터 쉼표 · 괄호가 섞인 글자도 요청하지 않는다', (tester) async {
      final server = await open(tester);
      final before = server.to('/admin/actions').length;

      await submit(tester, '$idA,or=(x)');

      expect(server.to('/admin/actions'), hasLength(before));
      expect(find.text('id 모양이 아니에요'), findsOneWidget);
    });

    testWidgets('칸을 비우고 엔터 → 전체 기록을 다시', (tester) async {
      final server = await open(tester);
      await submit(tester, idA);

      await submit(tester, '');

      expect(server.to('/admin/actions').last.url.queryParameters, isEmpty);
      expect(find.byKey(const ValueKey('action-row-a1')), findsOneWidget);
    });

    testWidgets('그 id 로 남은 기록이 없으면 "그 id 로 남은 기록이 없어요"', (tester) async {
      await open(tester);

      await submit(tester, 'ffffffff-0000-4000-8000-000000000000');

      expect(find.text('그 id 로 남은 기록이 없어요'), findsOneWidget);
      expect(find.text('기록이 없어요'), findsNothing);
    });
  });

  group('더 보기', () {
    testWidgets('쪽이 남았을 때만 [더 보기](Secondary) — 누르면 before 로 이어 붙이고, 끝이면 사라진다', (tester) async {
      final server = FakeStatsServer()..pageSize = 2;
      await open(tester, server: server);

      expect(find.byKey(const ValueKey('action-row-a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('action-row-a3')), findsNothing);
      final more = find.widgetWithText(AdminButton, '더 보기');
      expect(tester.widget<AdminButton>(more).variant, AdminButtonVariant.secondary);

      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(server.to('/admin/actions').last.url.queryParameters, {'before': '2026-10-18T05:21:00+00:00|a2'});
      expect(find.byKey(const ValueKey('action-row-a1')), findsOneWidget);
      expect(find.byKey(const ValueKey('action-row-a3')), findsOneWidget);
      expect(find.widgetWithText(AdminButton, '더 보기'), findsNothing);
    });

    testWidgets('검색해도 더 보기는 같은 대상 id 로 이어 받는다', (tester) async {
      final server = FakeStatsServer()
        ..pageSize = 1
        ..actions = [
          actionRow('b1', '2026-10-18T05:30:00+00:00', 'profile_note', targetType: 'profile', targetId: idA),
          actionRow('b2', '2026-10-18T05:20:00+00:00', 'profile_note', targetType: 'profile', targetId: idA),
        ];
      await open(tester, server: server);

      await submit(tester, idA);
      await tester.tap(find.widgetWithText(AdminButton, '더 보기'));
      await tester.pumpAndSettle();

      expect(server.to('/admin/actions').last.url.queryParameters, {'target': idA, 'before': '2026-10-18T05:30:00+00:00|b1'});
    });
  });

  group('받는 중 · 빈 목록 · 못 받음', () {
    testWidgets('비면 "기록이 없어요"', (tester) async {
      await open(tester, server: FakeStatsServer()..actions = []);

      expect(find.text('기록이 없어요'), findsOneWidget);
      expect(key('action-table'), findsNothing);
    });

    testWidgets('받는 중 안내 → 끝나면 사라진다', (tester) async {
      final hold = Completer<void>();
      await open(tester, server: FakeStatsServer()..holdActions = hold, settle: false);
      await tester.pump();
      await tester.pump();

      expect(find.text('작업 기록을 불러오고 있어요'), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text('작업 기록을 불러오고 있어요'), findsNothing);
    });

    testWidgets('못 받으면 오류 틀 + [다시 시도] — 검색칸은 그대로 쓸 수 있다', (tester) async {
      final server = FakeStatsServer()..actionsFailure = 500;
      await open(tester, server: server);

      expect(find.text('작업 기록을 불러오지 못했어요'), findsOneWidget);
      server.actionsFailure = null;
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('action-row-a1')), findsOneWidget);
    });

    testWidgets('읽기만 한다 — GET 이외를 보내지 않는다', (tester) async {
      final server = await open(tester);
      await submit(tester, idA);

      expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
    });
  });
}
