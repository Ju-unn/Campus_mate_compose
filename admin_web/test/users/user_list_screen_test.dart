import 'dart:async';

import 'package:campus_mate_admin/app.dart';
import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/users/user_controller.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../helpers/fakes.dart';
import '../helpers/user_fakes.dart';

/// A5 사용자 찾기(pen tH5Lz · 1440×900, 값표 A + PNG A5_사용자_찾기 · _닉네임_id_모드 · _결과없음 측정) — 그리고 학교 메일 보안.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');
  const mail = 'alice.test@campus.ac.kr';

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<FakeUserServer> openList(WidgetTester tester, {FakeUserServer? server, bool settle = true}) async {
    final fake = server ?? FakeUserServer(users: [userRow('8f3a1b2c-0000-4000-8000-000000000c21')]);
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: fake.api(), initialPath: '/users', settle: settle);
    return fake;
  }

  Finder field() => find.byType(TextField);
  Finder button(String label) => find.widgetWithText(AdminButton, label);
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;

  group('pen 배치(tH5Lz)', () {
    testWidgets('TopBar "사용자", 칩 줄 y96 높이 36 · 칩 사이 8, 기본은 "닉네임 · id" 가 켜짐(ink 바탕)', (tester) async {
      await openList(tester);

      expect(find.text('사용자'), findsNWidgets(2)); // 메뉴 + TopBar
      final first = find.widgetWithText(AdminChip, '닉네임 · id');
      final second = find.widgetWithText(AdminChip, '학교 메일');
      expect(tester.getRect(first).topLeft, const Offset(272, 96));
      expect(tester.getSize(first).height, 36);
      expect(tester.getRect(second).left - tester.getRect(first).right, 8);
      expect(tester.widget<AdminChip>(first).selected, isTrue);
      expect(tester.widget<AdminChip>(second).selected, isFalse);
    });

    testWidgets('검색 줄 y156: 칸 420×44(자리 "닉네임 또는 프로필 id") → 12 → [검색] 주 단추 44', (tester) async {
      await openList(tester);

      expect(tester.getRect(find.byKey(const ValueKey('user-search-box'))), const Rect.fromLTWH(272, 156, 420, 44));
      // 칸 테두리가 44 를 채운다(글자 높이로 쪼그라들지 않는다) — 글자는 세로 가운데, 돋보기 16 은 x 284
      expect(tester.getSize(find.descendant(of: find.byKey(const ValueKey('user-search-box')), matching: find.byType(InputDecorator))).height, 44);
      expect(tester.getRect(find.byIcon(LucideIcons.search)).left, 284);
      expect(tester.getRect(find.byIcon(LucideIcons.search)).width, 16);
      final search = button('검색');
      expect(tester.getRect(search).left, 704);
      expect(tester.getRect(search).top, 156);
      expect(tester.getSize(search).height, 44);
      expect(find.text('닉네임 또는 프로필 id'), findsOneWidget);
      final hint = find.text('닉네임 또는 프로필 id');
      expect((styleOf(tester, hint).fontSize, styleOf(tester, hint).color), (14, AdminColors.muted));
    });

    testWidgets('안내 줄 y224: info 16 + 8 + 12 web-muted — 두 방식 모두 같은 글', (tester) async {
      await openList(tester);

      final note = find.text('학교 메일은 정확히 일치해야 찾아요. 검색어는 기록되지 않아요.');
      expect(tester.getRect(note).left, 296);
      expect(tester.getRect(note).top, 224);
      expect((styleOf(tester, note).fontSize, styleOf(tester, note).color), (12, AdminColors.muted));
    });

    testWidgets('표 y264: 폭 가득 1136 · 머리 44 + 줄 52, 칸 x 288 · 468 · 688 · 868 · 988 · 1138(안쪽 16)', (tester) async {
      await openList(tester);

      expect(tester.getRect(find.byKey(const ValueKey('user-table'))), const Rect.fromLTWH(272, 264, 1136, 44 + 52));
      for (final (text, x) in [('닉네임', 288.0), ('프로필 id', 468.0), ('학교', 688.0), ('상태', 868.0), ('가입일', 988.0), ('받은 신고', 1138.0)]) {
        expect(tester.getRect(find.text(text).first).left, x, reason: text);
      }
      final head = find.text('프로필 id');
      expect((styleOf(tester, head).fontSize, styleOf(tester, head).fontWeight, styleOf(tester, head).color), (12, FontWeight.w700, AdminColors.muted));
      expect(find.text('닉네임A'), findsOneWidget);
      expect(find.text('8f3a…c21'), findsOneWidget);
      expect(find.text('서울대학교'), findsOneWidget);
      expect(find.text('2026-09-30'), findsOneWidget);
      expect(find.text('0건'), findsOneWidget);
      final badge = tester.widget<StatusBadge>(find.byType(StatusBadge).last);
      expect((badge.label, badge.tone), ('승인', StatusTone.success));
    });

    testWidgets('상태 배지: 정지 danger · 탈퇴 neutral · 가입 중(닉네임 없음)은 "—" + warning', (tester) async {
      final server = FakeUserServer(
        users: [
          userRow('a1', status: 'suspended'),
          userRow('a2', status: 'withdrawn'),
          userRow('a3', nickname: null, university: null, status: 'pending'),
        ],
      );
      await openList(tester, server: server);

      final badges = tester.widgetList<StatusBadge>(find.descendant(of: find.byKey(const ValueKey('user-table')), matching: find.byType(StatusBadge))).toList();
      expect([for (final b in badges) (b.label, b.tone)], [('정지', StatusTone.danger), ('탈퇴', StatusTone.neutral), ('가입 중', StatusTone.warning)]);
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('결과 없음(A5_사용자_찾기_결과없음): 표 자리에 높이 240 빈 틀 — "찾은 사용자가 없어요" + "입력한 닉네임 · id 를 다시 확인해 보세요"', (tester) async {
      await openList(tester, server: FakeUserServer(users: []));

      expect(find.byType(AdminTableEmpty), findsOneWidget);
      expect(find.text('찾은 사용자가 없어요'), findsOneWidget);
      expect(find.text('입력한 닉네임 · id 를 다시 확인해 보세요'), findsOneWidget);
      expect(tester.getRect(find.byType(AdminTableEmpty)), const Rect.fromLTWH(272, 264, 1136, 240));
    });
  });

  group('찾기', () {
    testWidgets('처음에는 가입 최근 순 목록(쿼리 없음), 닉네임을 쓰고 [검색] 하면 q 로 찾는다', (tester) async {
      final server = await openList(tester);
      expect(server.requests.where((r) => r.url.path == '/admin/users').single.url.queryParameters, isEmpty);

      await tester.enterText(field(), '닉네임A');
      await tester.tap(button('검색'));
      await tester.pumpAndSettle();

      expect(server.requests.where((r) => r.url.path == '/admin/users').last.url.queryParameters, {'q': '닉네임A'});
    });

    testWidgets('Enter 로도 찾는다', (tester) async {
      final server = await openList(tester);

      await tester.enterText(field(), '닉네임A');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(server.requests.where((r) => r.url.path == '/admin/users'), hasLength(2));
    });

    testWidgets('줄을 누르면 그 사람의 상세 주소 /users/{id}', (tester) async {
      final server = await openList(tester);
      server.details['8f3a1b2c-0000-4000-8000-000000000c21'] = userDetailJson('8f3a1b2c-0000-4000-8000-000000000c21');

      await tester.tap(find.byKey(const ValueKey('user-row-8f3a1b2c-0000-4000-8000-000000000c21')));
      await tester.pumpAndSettle();

      expect(locationOf(tester), '/users/8f3a1b2c-0000-4000-8000-000000000c21');
      expect(find.text('사용자 상세'), findsOneWidget);
    });

    testWidgets('받는 중: 도는 아이콘 + 글, [검색] 은 요청 중 표시. 못 받으면 오류 틀 + [다시 시도]', (tester) async {
      final server = FakeUserServer()..holdList = Completer<void>();
      await openList(tester, server: server, settle: false);
      await tester.pump();

      expect(find.byType(AdminLoader), findsWidgets);
      expect(find.text('사용자를 찾고 있어요'), findsOneWidget);
      server.holdList!.complete();
      await tester.pumpAndSettle();
      expect(find.text('사용자를 찾고 있어요'), findsNothing);

      server.listFailure = 500;
      await tester.tap(button('검색'));
      await tester.pumpAndSettle();
      expect(find.text('목록을 불러오지 못했어요'), findsOneWidget);
      server.listFailure = null;
      await tester.tap(button('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('목록을 불러오지 못했어요'), findsNothing);
      expect(find.text('닉네임A'), findsOneWidget);
    });
  });

  group('학교 메일 찾기(대장 결정 2 · 설계 §14-3)', () {
    Future<FakeUserServer> mailMode(WidgetTester tester) async {
      final server = FakeUserServer(users: [userRow('u1')])..mailOwners[mail] = 'u1';
      await openList(tester, server: server);
      await tester.tap(find.text('학교 메일'));
      await tester.pumpAndSettle();
      return server;
    }

    String stateText(WidgetTester tester) {
      final container = ProviderScope.containerOf(tester.element(find.byType(AdminApp)));
      final state = container.read(userSearchProvider);
      return '${state.results} ${state.mode} ${state.resultMode}';
    }

    testWidgets('칩을 누르면 자리 글자가 "학교 메일 주소 (정확히 일치)" 로 바뀌고 칩 켜짐이 옮겨 간다', (tester) async {
      await mailMode(tester);

      expect(find.text('학교 메일 주소 (정확히 일치)'), findsOneWidget);
      expect(tester.widget<AdminChip>(find.widgetWithText(AdminChip, '학교 메일')).selected, isTrue);
      expect(tester.widget<AdminChip>(find.widgetWithText(AdminChip, '닉네임 · id')).selected, isFalse);
    });

    testWidgets('메일은 POST 본문으로만 간다 — 요청 주소 · 쿼리에 메일이 없고, 찾으면 칸이 비고, 주소창 · provider 상태에도 없다', (tester) async {
      final server = await mailMode(tester);

      await tester.enterText(field(), mail);
      await tester.tap(button('검색'));
      await tester.pumpAndSettle();

      final post = server.requests.singleWhere((r) => r.method == 'POST' && r.url.path == '/admin/users/search');
      expect(post.body, contains(mail));
      for (final request in server.requests) {
        expect(request.url.toString(), isNot(contains('alice')), reason: request.url.toString());
        expect(request.url.toString(), isNot(contains('@')));
      }
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(locationOf(tester), '/users');
      expect(stateText(tester), isNot(contains('alice')));
      expect(find.text('닉네임A'), findsOneWidget);
    });

    testWidgets('못 찾아도 칸이 빈다 — "찾은 사용자가 없어요" + "그 학교 메일로 가입한 사용자가 없어요"', (tester) async {
      await mailMode(tester);

      await tester.enterText(field(), 'nobody@campus.ac.kr');
      await tester.tap(button('검색'));
      await tester.pumpAndSettle();

      expect(find.text('찾은 사용자가 없어요'), findsOneWidget);
      expect(find.text('그 학교 메일로 가입한 사용자가 없어요'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(find.textContaining('nobody'), findsNothing);
    });

    testWidgets('오류(서버 500 · 모양 422)여도 칸이 빈다, 422 는 "학교 메일 모양이 아니에요"', (tester) async {
      final server = await mailMode(tester);

      server.searchFailure = 500;
      await tester.enterText(field(), mail);
      await tester.tap(button('검색'));
      await tester.pumpAndSettle();
      expect(find.text('목록을 불러오지 못했어요'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);

      server.searchFailure = 422;
      await tester.enterText(field(), 'not-a-mail');
      await tester.tap(button('검색'));
      await tester.pumpAndSettle();
      expect(find.text('학교 메일 모양이 아니에요'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(stateText(tester), isNot(contains('not-a-mail')));
    });

    testWidgets('빈 칸으로는 메일 찾기를 보내지 않고, 칩을 바꾸면 칸도 비운다', (tester) async {
      final server = await mailMode(tester);

      await tester.tap(button('검색'));
      await tester.pumpAndSettle();
      expect(server.requests.where((r) => r.url.path == '/admin/users/search'), isEmpty);

      await tester.enterText(field(), 'typed@campus.ac.kr');
      await tester.tap(find.text('닉네임 · id'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
    });

    testWidgets('닉네임 칸은 36자(서버 q 상한), 메일 칸은 254자까지', (tester) async {
      await mailMode(tester);
      await tester.enterText(field(), 'a' * 300);
      expect(tester.widget<TextField>(field()).controller!.text.length, 254);
      await tester.tap(find.text('닉네임 · id'));
      await tester.pumpAndSettle();
      await tester.enterText(field(), 'a' * 50);
      expect(tester.widget<TextField>(field()).controller!.text.length, 36);
    });

    testWidgets('닉네임 · id 모드에서 칸에 "@" 가 있으면 요청을 보내지 않는다 — 오류 줄 + [검색] 잠김 (메일이 GET 주소로 나가지 않게)', (tester) async {
      final server = await openList(tester);
      final before = server.requests.length;

      await tester.enterText(field(), mail);
      await tester.pump();

      const message = "학교 메일은 '학교 메일' 칩을 눌러 찾아 주세요";
      expect(find.text(message), findsOneWidget);
      expect(find.byType(ErrorRow), findsOneWidget);
      expect(tester.widget<AdminButton>(button('검색')).onPressed, isNull);
      await tester.tap(button('검색'), warnIfMissed: false);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(server.requests.length, before);
      for (final request in server.requests) {
        expect(request.url.toString(), isNot(contains('@')));
      }
      // 지우면 오류 줄이 사라지고 다시 찾을 수 있다
      await tester.enterText(field(), '닉네임A');
      await tester.pump();
      expect(find.text(message), findsNothing);
      expect(tester.widget<AdminButton>(button('검색')).onPressed, isNotNull);
      // 학교 메일 칩에서는 막지 않는다
      await tester.tap(find.text('학교 메일'));
      await tester.pumpAndSettle();
      await tester.enterText(field(), mail);
      await tester.pump();
      expect(find.text(message), findsNothing);
      expect(tester.widget<AdminButton>(button('검색')).onPressed, isNotNull);
    });

    testWidgets('메일 칸은 글자 제안 · 자동 고침을 끈다(브라우저에 남지 않게)', (tester) async {
      await mailMode(tester);

      final input = tester.widget<TextField>(field());
      expect((input.enableSuggestions, input.autocorrect, input.enableIMEPersonalizedLearning), (false, false, false));
    });
  });
}
