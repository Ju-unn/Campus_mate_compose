import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../helpers/fakes.dart';
import '../helpers/stats_fakes.dart';

/// A9 매칭 현황(pen H5Pocy, 1440×1200 — 값표 w4_pen_values + PNG A9_매칭_현황 측정). 서버 계약은 D4(matching · universities).
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<FakeStatsServer> openMatching(WidgetTester tester, {FakeStatsServer? server, bool settle = true}) async {
    final fake = server ?? FakeStatsServer();
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: fake.api(), initialPath: '/matching', size: const Size(1440, 1200), settle: settle);
    return fake;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;
  // 같은 글자 칩이 신청 목록 필터에도 있다 — 위쪽(매칭 쌍) 필터가 문서 순서로 먼저다
  Finder chip(String label) => find.widgetWithText(AdminChip, label).first;
  Finder requestChip(String label) => find.widgetWithText(AdminChip, label).last;
  Finder inTable(Finder what) => find.descendant(of: key('match-table'), matching: what);
  Finder inRequests(Finder what) => find.descendant(of: key('request-table'), matching: what);

  group('pen 배치(H5Pocy)', () {
    testWidgets('TopBar "매칭 현황"(메뉴 이름은 "매칭")', (tester) async {
      await openMatching(tester);

      expect(find.text('매칭 현황'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('nav-matching')), matching: find.text('매칭')), findsOneWidget);
    });

    testWidgets('숫자 카드 4장 y96: 272 × 146, 사이 16 — 오늘 수락 / 누적 수락 "18 / 436" · 수락한 사람 수 "312명" · 매칭 성립 쌍 "67쌍" · 카톡 공유 쌍 "41쌍 · 62%"', (tester) async {
      await openMatching(tester);

      final cards = find.byType(StatCard);
      expect(cards, findsNWidgets(4));
      expect([for (var i = 0; i < 4; i++) tester.getRect(cards.at(i))], const [
        Rect.fromLTWH(272, 96, 272, 146),
        Rect.fromLTWH(560, 96, 272, 146),
        Rect.fromLTWH(848, 96, 272, 146),
        Rect.fromLTWH(1136, 96, 272, 146),
      ]);
      for (final (label, value) in [
        ('오늘 수락 / 누적 수락', '18 / 436'),
        ('수락한 사람 수', '312명'),
        ('매칭 성립 쌍', '67쌍'),
        ('카톡 공유 쌍', '41쌍 · 62%'),
      ]) {
        expect(find.descendant(of: find.widgetWithText(StatCard, label), matching: find.text(value)), findsOneWidget, reason: label);
      }
      final label = find.text('오늘 수락 / 누적 수락');
      expect((styleOf(tester, label).fontSize, styleOf(tester, label).fontWeight, styleOf(tester, label).color), (14, FontWeight.w600, AdminColors.muted));
      expect(tester.getTopLeft(label), const Offset(296, 120));
    });

    testWidgets('아래 줄은 14 muted — "어제 14건"(서버 accepts_yesterday) · "누적" · "누적" · "매칭 대비"', (tester) async {
      await openMatching(tester);

      for (final text in ['어제 14건', '매칭 대비']) {
        expect((styleOf(tester, find.text(text)).fontSize, styleOf(tester, find.text(text)).color), (14, AdminColors.muted), reason: text);
      }
      expect(find.text('누적'), findsNWidgets(2));
      expect(styleOf(tester, find.text('누적').first).fontWeight, FontWeight.w400);
    });

    testWidgets('서버가 accepts_yesterday 를 주지 않으면 "어제" 줄을 그리지 않는다(추측 금지)', (tester) async {
      await openMatching(tester, server: FakeStatsServer()..matchSummary = matchSummaryJson(yesterday: null));

      expect(find.textContaining('어제'), findsNothing);
      expect(find.text('18 / 436'), findsOneWidget);
    });

    testWidgets('share_rate 가 null(매칭 0건)이면 "0쌍 · -"', (tester) async {
      await openMatching(tester, server: FakeStatsServer()..matchSummary = matchSummaryJson(matches: 0, shared: 0, shareRate: null));

      expect(find.text('0쌍 · -'), findsOneWidget);
    });

    testWidgets('그래프 카드 y262: 1136 × 316 · 제목 + 알약 "최근 30일" — 그래프 1080×240 (292,318), 눈금 5줄(0 · 10 · 20 · 30 · 40), 범례 "수락" · "매칭" · "카톡 공유"', (tester) async {
      await openMatching(tester);

      expect(tester.getRect(key('matching-card')), const Rect.fromLTWH(272, 262, 1136, 316));
      expect(find.text('수락 · 매칭 · 카톡 공유 추이'), findsOneWidget);
      expect(find.text('최근 30일'), findsOneWidget);
      expect(tester.getRect(key('chart-matching')), const Rect.fromLTWH(292, 318, 1080, 240));
      for (final tick in ['0', '10', '20', '30', '40']) {
        expect(find.descendant(of: key('chart-matching'), matching: find.text(tick)), findsOneWidget, reason: tick);
      }
      for (final name in ['수락', '매칭', '카톡 공유']) {
        expect(find.descendant(of: key('chart-matching'), matching: find.text(name)), findsOneWidget, reason: name);
      }
    });

    testWidgets('표 제목 "누가 누구랑 매칭됐나" (272,598) 16/700 → 필터 줄 y640(Select 200×36 "전체 학교" + 칩 4개 사이 12)', (tester) async {
      await openMatching(tester);

      final title = find.text('누가 누구랑 매칭됐나');
      expect(tester.getTopLeft(title), const Offset(272, 598));
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (16, FontWeight.w700));
      expect(tester.getRect(key('school-select')), const Rect.fromLTWH(272, 640, 200, 36));
      expect(find.descendant(of: key('school-select'), matching: find.text('전체 학교')), findsOneWidget);
      final chips = [for (final label in ['전체', '대화 중', '카톡 공유 완료', '닫힘']) tester.getRect(chip(label))];
      expect(chips.first.left, 484);
      expect([for (final c in chips) c.top], [640, 640, 640, 640]);
      expect([for (final c in chips) c.height], [36, 36, 36, 36]);
      for (var i = 1; i < chips.length; i++) {
        expect(chips[i].left, chips[i - 1].right + 12);
      }
      expect(tester.widget<AdminChip>(chip('전체')).selected, isTrue);
      expect(tester.widget<AdminChip>(chip('닫힘')).selected, isFalse);
    });

    testWidgets('안내 줄 y696: info 16 muted + "사진 · 카톡 아이디 · 대화는 보이지 않아요. 최근 순으로 보여요." 12 muted', (tester) async {
      await openMatching(tester);

      expect(find.byIcon(LucideIcons.info), findsNWidgets(2)); // 매칭 쌍 목록 · 신청 목록 안내 줄
      final note = find.text('사진 · 카톡 아이디 · 대화는 보이지 않아요. 최근 순으로 보여요.').first; // 신청 목록 구역에도 같은 안내가 있다
      expect((styleOf(tester, note).fontSize, styleOf(tester, note).color), (12, AdminColors.muted));
      expect(tester.getTopLeft(note).dy, closeTo(696, 1));
    });

    testWidgets('표 (272,732) 1136 × (44 + 52 × 7), 머리 글자 x: 매칭 시각 288 · A 448 · B 738 · 상태 988 · 카톡 공유 시각 1148, 관계 열(40)은 머리 글자 없음', (tester) async {
      await openMatching(tester);

      expect(tester.getRect(key('match-table')), const Rect.fromLTWH(272, 732, 1136, 44 + 52 * 7));
      expect(
        [for (final head in ['매칭 시각', 'A (닉네임 · 학교)', 'B (닉네임 · 학교)', '상태', '카톡 공유 시각']) tester.getTopLeft(inTable(find.text(head))).dx],
        [288, 448, 738, 988, 1148],
      );
      // 열은 6개: 사진 · 카톡 아이디 · 대화 열이 없다
      expect(inTable(find.text('카톡 아이디')), findsNothing);
    });

    testWidgets('첫 줄: 매칭 시각 "10/18 14:02"(한국 시각) · A "닉네임A · 서울대학교" 14/600 primary-text · "—" muted · B · 배지 "대화 중" · 공유 시각 "-"', (tester) async {
      await openMatching(tester);

      final time = tester.getTopLeft(inTable(find.text('10/18 14:02')));
      expect(time.dx, 288);
      expect(time.dy, closeTo(732 + 44 + 15.5, 0.5));
      final a = find.byKey(const ValueKey('match-m1-a'));
      expect(find.descendant(of: a, matching: find.text('닉네임A · 서울대학교')), findsOneWidget);
      final aStyle = styleOf(tester, find.descendant(of: a, matching: find.text('닉네임A · 서울대학교')));
      expect((aStyle.fontSize, aStyle.fontWeight, aStyle.color), (14, FontWeight.w600, AdminColors.primaryText));
      expect(tester.getTopLeft(find.descendant(of: a, matching: find.text('닉네임A · 서울대학교'))).dx, 448);
      expect(find.descendant(of: find.byKey(const ValueKey('match-m1-b')), matching: find.text('닉네임B · 서울대학교')), findsOneWidget);
      final dash = find.descendant(of: key('match-row-m1'), matching: find.text('—'));
      expect(styleOf(tester, dash).color, AdminColors.muted);
      expect(tester.getTopLeft(dash).dx, 698);
      expect(tester.getTopLeft(find.descendant(of: key('match-row-m1'), matching: find.byType(StatusBadge))).dx, 988);
      final noShare = find.descendant(of: key('match-row-m1'), matching: find.text('-'));
      expect(tester.getTopLeft(noShare).dx, 1148);
      expect(styleOf(tester, noShare).color, AdminColors.muted);
    });

    testWidgets('상태 배지: 대화 중 primary · 카톡 공유 완료 success · 닫힘 neutral, 공유된 줄의 시각 "10/18 12:40"(pen)', (tester) async {
      await openMatching(tester);

      StatusTone tone(String label) => tester.widget<StatusBadge>(find.descendant(of: key('match-table'), matching: find.widgetWithText(StatusBadge, label)).first).tone;
      expect(tone('대화 중'), StatusTone.primary);
      expect(tone('카톡 공유 완료'), StatusTone.success);
      expect(tone('닫힘'), StatusTone.neutral);
      expect(tester.getTopLeft(inTable(find.text('10/18 11:25'))).dx, 288);
      expect(inTable(find.text('10/18 12:40')), findsOneWidget);
    });

    testWidgets('아래 안내 "닉네임을 누르면 사용자 상세로 가요." 12 muted (272,1160)', (tester) async {
      await openMatching(tester);

      final hint = find.text('닉네임을 누르면 사용자 상세로 가요.');
      expect(tester.getTopLeft(hint), const Offset(272, 732 + 408 + 20));
      expect((styleOf(tester, hint).fontSize, styleOf(tester, hint).color), (12, AdminColors.muted));
    });
  });

  testWidgets('좁은 창(1280)에서도 넘치지 않는다 — 숫자 카드 232 폭, 그래프는 카드 안 폭에 맞춘다', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: FakeStatsServer().api(), initialPath: '/matching', size: const Size(1280, 1200));

    // 내용 976 → 카드 (976 − 16 × 3) / 4 = 232, 그래프 976 − 40 = 936(1080 보다 좁다)
    expect(tester.getSize(find.byType(StatCard).first).width, 232);
    expect(tester.getSize(key('chart-matching')).width, 936);
    expect(tester.takeException(), isNull);
  });

  testWidgets('글자를 2배로 키워도 상태 배지가 칸(160)을 넘치지 않는다 — 칸에 맞춰 줄어든다(셸 메뉴의 기존 넘침은 따로)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.toString());
    await openMatching(tester);
    FlutterError.onError = previous;

    expect(errors.where((e) => e.contains('status_badge.dart')), isEmpty);
    expect(find.text('카톡 공유 완료'), findsWidgets);
  });

  group('닉네임 · 탈퇴한 사람', () {
    testWidgets('닉네임을 누르면 그 사람의 사용자 상세로', (tester) async {
      await openMatching(tester);

      await tester.tap(find.byKey(const ValueKey('match-m2-b')));
      await tester.pumpAndSettle();

      expect(locationOf(tester), '/users/m2-b');
    });

    testWidgets('탈퇴로 없는 사람은 링크 없이 "탈퇴한 사용자" muted', (tester) async {
      final server = FakeStatsServer()
        ..pairs = [pairRow('m9', '2026-10-18T05:02:00+00:00', 'closed', b: {'id': null, 'nickname': null, 'university': null})];
      await openMatching(tester, server: server);

      final gone = find.text('탈퇴한 사용자');
      expect(styleOf(tester, gone).color, AdminColors.muted);
      expect(find.byKey(const ValueKey('match-m9-b')), findsNothing);
      await tester.tap(gone);
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/matching');
    });

    testWidgets('주소에 넣을 수 없는 모양의 id 는 링크로 만들지 않는다(경로 id 검사)', (tester) async {
      final server = FakeStatsServer()
        ..pairs = [pairRow('m9', '2026-10-18T05:02:00+00:00', 'closed', a: {'id': '../me', 'nickname': '닉네임X', 'university': '서울대학교'})];
      await openMatching(tester, server: server);

      expect(find.byKey(const ValueKey('match-m9-a')), findsNothing);
      expect(find.text('닉네임X · 서울대학교'), findsOneWidget); // 글자는 그대로 보인다(링크만 없다)
    });

    testWidgets('서버 글자는 그대로의 일반 글자 — 사진 · 카톡 아이디 · 대화는 어디에도 없다', (tester) async {
      final server = FakeStatsServer()
        ..pairs = [pairRow('m1', '2026-10-18T05:02:00+00:00', 'chatting')..addAll({'kakao_id': 'secretkakao', 'photo_path': 'p/1.jpg', 'last_message': '안녕하세요'})];
      await openMatching(tester, server: server);

      expect(find.textContaining('secretkakao'), findsNothing);
      expect(find.textContaining('안녕하세요'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
    });
  });

  group('필터', () {
    testWidgets('칩을 누르면 처음부터 다시 받는다 — 카톡 공유 완료 → status=shared, 전체 → status 없음', (tester) async {
      final server = await openMatching(tester);
      expect(server.to('/admin/matching/pairs').single.url.queryParameters, isEmpty);

      await tester.tap(chip('카톡 공유 완료'));
      await tester.pumpAndSettle();

      expect(server.to('/admin/matching/pairs').last.url.queryParameters, {'status': 'shared'});
      expect(tester.widget<AdminChip>(chip('카톡 공유 완료')).selected, isTrue);
      expect(find.byKey(const ValueKey('match-row-m1')), findsNothing);
      expect(find.byKey(const ValueKey('match-row-m2')), findsOneWidget);

      await tester.tap(chip('전체'));
      await tester.pumpAndSettle();
      expect(server.to('/admin/matching/pairs').last.url.queryParameters, isEmpty);
      expect(find.byKey(const ValueKey('match-row-m1')), findsOneWidget);
    });

    testWidgets('대화 중 · 닫힘 칩은 status=chatting · closed', (tester) async {
      final server = await openMatching(tester);

      await tester.tap(chip('대화 중'));
      await tester.pumpAndSettle();
      expect(server.to('/admin/matching/pairs').last.url.queryParameters, {'status': 'chatting'});
      await tester.tap(chip('닫힘'));
      await tester.pumpAndSettle();
      expect(server.to('/admin/matching/pairs').last.url.queryParameters, {'status': 'closed'});
    });

    testWidgets('학교 Select 옵션은 include_empty=true 의 학교 목록 + "전체 학교" — 고르면 university=학교 id', (tester) async {
      final server = await openMatching(tester);
      expect(server.to('/admin/universities').single.url.queryParameters, {'include_empty': 'true'});

      await tester.tap(key('school-select'));
      await tester.pump();
      expect(find.byKey(const ValueKey('school-select-option-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('school-select-option-3')), findsOneWidget); // 전체 + 3곳
      await tester.tap(find.byKey(const ValueKey('school-select-option-2'))); // 연세대학교
      await tester.pumpAndSettle();

      expect(server.to('/admin/matching/pairs').last.url.queryParameters, {'university': 'uni-연세대학교'});
      expect(find.descendant(of: key('school-select'), matching: find.text('연세대학교')), findsOneWidget);
      expect(find.byKey(const ValueKey('match-row-m2')), findsOneWidget);
      expect(find.byKey(const ValueKey('match-row-m4')), findsNothing);
    });

    testWidgets('학교와 상태를 같이 걸면 두 쿼리가 함께 간다', (tester) async {
      final server = await openMatching(tester);

      await tester.tap(chip('카톡 공유 완료'));
      await tester.pumpAndSettle();
      await tester.tap(key('school-select'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('school-select-option-1')));
      await tester.pumpAndSettle();

      expect(server.to('/admin/matching/pairs').last.url.queryParameters, {'status': 'shared', 'university': 'uni-서울대학교'});
    });
  });

  group('더 보기(next_before 커서)', () {
    testWidgets('쪽이 남았을 때만 표 아래 [더 보기] — 누르면 before 로 다음 쪽을 이어 붙이고, 끝이면 사라진다', (tester) async {
      final server = FakeStatsServer()..pageSize = 3;
      await openMatching(tester, server: server);

      expect(find.byType(AdminChip), findsNWidgets(4 + 5)); // 매칭 쌍 필터 4 + 신청 필터 5
      expect(find.byKey(const ValueKey('match-row-m3')), findsOneWidget);
      expect(find.byKey(const ValueKey('match-row-m4')), findsNothing);
      final more = find.widgetWithText(AdminButton, '더 보기');
      expect(tester.widget<AdminButton>(more).variant, AdminButtonVariant.secondary);

      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(server.to('/admin/matching/pairs').last.url.queryParameters, {'before': '2026-10-17T12:10:00+00:00|m3'});
      expect(find.byKey(const ValueKey('match-row-m3')), findsOneWidget); // 앞 줄은 그대로
      expect(find.byKey(const ValueKey('match-row-m6')), findsOneWidget);
      expect(find.widgetWithText(AdminButton, '더 보기'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(AdminButton, '더 보기'));
      await tester.tap(find.widgetWithText(AdminButton, '더 보기'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('match-row-m7')), findsOneWidget);
      expect(find.widgetWithText(AdminButton, '더 보기'), findsNothing);
    });

    testWidgets('필터를 바꾸면 처음부터 다시 받는다(before 없이)', (tester) async {
      final server = FakeStatsServer()..pageSize = 3;
      await openMatching(tester, server: server);
      await tester.ensureVisible(find.widgetWithText(AdminButton, '더 보기'));
      await tester.tap(find.widgetWithText(AdminButton, '더 보기'));
      await tester.pumpAndSettle();

      await tester.tap(chip('닫힘'));
      await tester.pumpAndSettle();

      expect(server.to('/admin/matching/pairs').last.url.queryParameters, {'status': 'closed'});
      expect(find.byKey(const ValueKey('match-row-m5')), findsOneWidget);
      expect(find.byKey(const ValueKey('match-row-m1')), findsNothing);
    });

    testWidgets('더 받기에 실패하면 앞 줄은 그대로 두고 단추 위에 오류 줄', (tester) async {
      final server = FakeStatsServer()..pageSize = 3;
      await openMatching(tester, server: server);
      server.pairsFailure = 500;

      await tester.ensureVisible(find.widgetWithText(AdminButton, '더 보기'));
      await tester.tap(find.widgetWithText(AdminButton, '더 보기'));
      await tester.pumpAndSettle();

      expect(find.text('더 불러오지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('match-row-m3')), findsOneWidget);
      expect(find.widgetWithText(AdminButton, '더 보기'), findsOneWidget);
    });
  });

  group('받는 중 · 빈 목록 · 못 받음', () {
    testWidgets('목록이 비면 "조건에 맞는 매칭이 없어요"', (tester) async {
      await openMatching(tester, server: FakeStatsServer()..pairs = []);

      expect(find.text('조건에 맞는 매칭이 없어요'), findsOneWidget);
      expect(key('match-table'), findsNothing);
      expect(find.byType(StatCard), findsNWidgets(4)); // 위쪽은 그대로
    });

    testWidgets('목록 받는 중 안내 → 끝나면 사라진다', (tester) async {
      final hold = Completer<void>();
      await openMatching(tester, server: FakeStatsServer()..holdPairs = hold, settle: false);
      await tester.pump();
      await tester.pump();

      expect(find.text('매칭 목록을 불러오고 있어요'), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text('매칭 목록을 불러오고 있어요'), findsNothing);
    });

    testWidgets('목록을 못 받으면 오류 틀 + [다시 시도], 숫자 · 그래프는 그대로', (tester) async {
      final server = FakeStatsServer()..pairsFailure = 500;
      await openMatching(tester, server: server);

      expect(find.text('매칭 목록을 불러오지 못했어요'), findsOneWidget);
      expect(find.byType(StatCard), findsNWidgets(4));
      server.pairsFailure = null;
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('match-row-m1')), findsOneWidget);
    });

    testWidgets('숫자 · 그래프를 못 받으면 그 자리에 오류 틀 + [다시 시도], 목록은 그대로', (tester) async {
      final server = FakeStatsServer()..matchingFailure = 500;
      await openMatching(tester, server: server);

      expect(find.text('매칭 정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.byType(StatCard), findsNothing);
      expect(find.byKey(const ValueKey('match-row-m1')), findsOneWidget);
      server.matchingFailure = null;
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byType(StatCard), findsNWidgets(4));
    });

    testWidgets('읽기만 한다 — GET 이외를 보내지 않는다', (tester) async {
      final server = await openMatching(tester);

      expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
    });
  });

  group('누가 누구에게 대화를 신청했나', () {
    Future<FakeStatsServer> openRequests(WidgetTester tester, {FakeStatsServer? server}) async {
      final fake = await openMatching(tester, server: server);
      await tester.ensureVisible(find.text('누가 누구에게 대화를 신청했나'));
      await tester.pump();
      return fake;
    }

    testWidgets('맨 아래 구역: 제목 16/700 → 칩 "전체 · 응답 대기 · 수락 · 거절 · 만료"(전체 선택, 사이 12) → 안내 줄', (tester) async {
      await openRequests(tester);

      final title = find.text('누가 누구에게 대화를 신청했나');
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (16, FontWeight.w700));
      expect(tester.getTopLeft(title).dy, greaterThan(tester.getBottomLeft(key('match-table')).dy)); // 매칭 쌍 표보다 아래
      expect(find.byKey(const ValueKey('school-select')), findsOneWidget); // 학교 필터는 위쪽 하나뿐
      final chips = [for (final label in ['전체', '응답 대기', '수락', '거절', '만료']) tester.getRect(requestChip(label))];
      expect(chips.map((c) => c.top).toSet(), hasLength(1)); // 한 줄
      for (var i = 1; i < chips.length; i++) {
        expect(chips[i].left, chips[i - 1].right + 12);
      }
      expect(tester.widget<AdminChip>(requestChip('전체')).selected, isTrue);
      expect(tester.widget<AdminChip>(requestChip('만료')).selected, isFalse);
      expect(find.text('사진 · 카톡 아이디 · 대화는 보이지 않아요. 최근 순으로 보여요.'), findsNWidgets(2));
    });

    testWidgets('표 열: 신청 시각 · 신청한 사람 · (화살표) · 받은 사람 · 상대 응답 · 응답 시각 — 사진 · 카톡 아이디 · 대화 열이 없다', (tester) async {
      await openRequests(tester);

      for (final head in ['신청 시각', '신청한 사람 (닉네임 · 학교)', '받은 사람 (닉네임 · 학교)', '상대 응답', '응답 시각']) {
        expect(inRequests(find.text(head)), findsOneWidget, reason: head);
      }
      expect(inRequests(find.text('카톡 아이디')), findsNothing);
      expect(find.byKey(const ValueKey('request-row-r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('request-row-r4')), findsOneWidget);
    });

    testWidgets('첫 줄: 신청 시각 "10/18 14:02"(한국 시각) · 신청한 사람 · 받은 사람 "닉네임 · 학교" · 배지 "응답 대기" · 응답 시각 "-"', (tester) async {
      await openRequests(tester);

      final row = key('request-row-r1');
      expect(find.descendant(of: row, matching: find.text('10/18 14:02')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('request-r1-from')), matching: find.text('신청자r1 · 서울대학교')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('request-r1-to')), matching: find.text('받은이r1 · 연세대학교')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.widgetWithText(StatusBadge, '응답 대기')), findsOneWidget);
      final noReply = find.descendant(of: row, matching: find.text('-'));
      expect(styleOf(tester, noReply).color, AdminColors.muted);
      expect(find.descendant(of: row, matching: find.byIcon(LucideIcons.arrowRight)), findsOneWidget);
    });

    testWidgets('상태 배지 4가지와 응답 시각 — 수락 "10/17 23:30" · 거절 "10/16 13:00", 응답 대기 · 만료는 "-"', (tester) async {
      await openRequests(tester);

      StatusTone tone(String label) => tester.widget<StatusBadge>(inRequests(find.widgetWithText(StatusBadge, label))).tone;
      expect(tone('응답 대기'), StatusTone.warning);
      expect(tone('수락'), StatusTone.success);
      expect(tone('거절'), StatusTone.danger);
      expect(tone('만료'), StatusTone.neutral);
      expect(find.descendant(of: key('request-row-r2'), matching: find.text('10/17 23:30')), findsOneWidget);
      expect(find.descendant(of: key('request-row-r3'), matching: find.text('10/16 13:00')), findsOneWidget);
      expect(find.descendant(of: key('request-row-r4'), matching: find.text('-')), findsOneWidget);
    });

    testWidgets('닉네임을 누르면 그 사람의 사용자 상세로 — 탈퇴로 없는 사람은 링크 없이 "탈퇴한 사용자"', (tester) async {
      final server = FakeStatsServer()
        ..matchRequests = [
          requestRow('r1', '2026-10-18T05:02:00+00:00', 'waiting'),
          requestRow('r9', '2026-10-17T05:02:00+00:00', 'expired', target: {'id': null, 'nickname': null, 'university': null}),
        ];
      await openRequests(tester, server: server);

      expect(find.byKey(const ValueKey('request-r9-to')), findsNothing);
      expect(find.descendant(of: key('request-row-r9'), matching: find.text('탈퇴한 사용자')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('request-r1-to')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/users/r1-to');
    });

    testWidgets('서버 글자는 일반 글자 — 사진 · 카톡 아이디 · 대화는 어디에도 없다', (tester) async {
      final server = FakeStatsServer()
        ..matchRequests = [requestRow('r1', '2026-10-18T05:02:00+00:00', 'waiting')..addAll({'kakao_id': 'secretkakao', 'last_message': '안녕하세요'})];
      await openRequests(tester, server: server);

      expect(find.textContaining('secretkakao'), findsNothing);
      expect(find.textContaining('안녕하세요'), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('칩을 누르면 처음부터 다시 받는다 — 수락 → status=accepted, 전체 → status 없음, 매칭 쌍 목록은 그대로', (tester) async {
      final server = await openRequests(tester);
      expect(server.to('/admin/matching/requests').single.url.queryParameters, isEmpty);

      await tester.tap(requestChip('수락'));
      await tester.pumpAndSettle();

      expect(server.to('/admin/matching/requests').last.url.queryParameters, {'status': 'accepted'});
      expect(tester.widget<AdminChip>(requestChip('수락')).selected, isTrue);
      expect(find.byKey(const ValueKey('request-row-r1')), findsNothing);
      expect(find.byKey(const ValueKey('request-row-r2')), findsOneWidget);
      expect(server.to('/admin/matching/pairs'), hasLength(1)); // 위쪽 목록은 다시 받지 않는다

      await tester.tap(requestChip('전체'));
      await tester.pumpAndSettle();
      expect(server.to('/admin/matching/requests').last.url.queryParameters, isEmpty);
      expect(find.byKey(const ValueKey('request-row-r1')), findsOneWidget);
    });

    testWidgets('응답 대기 · 거절 · 만료 칩은 status=waiting · rejected · expired', (tester) async {
      final server = await openRequests(tester);

      for (final (label, status) in [('응답 대기', 'waiting'), ('거절', 'rejected'), ('만료', 'expired')]) {
        await tester.tap(requestChip(label));
        await tester.pumpAndSettle();
        expect(server.to('/admin/matching/requests').last.url.queryParameters, {'status': status}, reason: label);
      }
    });

    testWidgets('위쪽 매칭 쌍 칩은 신청 목록을 다시 받지 않는다', (tester) async {
      final server = await openRequests(tester);

      await tester.ensureVisible(chip('닫힘'));
      await tester.tap(chip('닫힘'));
      await tester.pumpAndSettle();

      expect(server.to('/admin/matching/requests'), hasLength(1));
      expect(server.to('/admin/matching/pairs').last.url.queryParameters, {'status': 'closed'});
    });

    testWidgets('쪽이 남았을 때만 [더 보기] — 누르면 before 로 다음 쪽을 이어 붙이고, 끝이면 사라진다', (tester) async {
      final server = FakeStatsServer()..matchRequestPageSize = 3;
      await openRequests(tester, server: server);

      expect(find.byKey(const ValueKey('request-row-r3')), findsOneWidget);
      expect(find.byKey(const ValueKey('request-row-r4')), findsNothing);
      final more = find.widgetWithText(AdminButton, '더 보기');
      expect(tester.widget<AdminButton>(more).variant, AdminButtonVariant.secondary);

      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(server.to('/admin/matching/requests').last.url.queryParameters, {'before': '2026-10-16T03:00:00+00:00|r3'});
      expect(find.byKey(const ValueKey('request-row-r3')), findsOneWidget); // 앞 줄은 그대로
      expect(find.byKey(const ValueKey('request-row-r4')), findsOneWidget);
      expect(find.widgetWithText(AdminButton, '더 보기'), findsNothing);
    });

    testWidgets('더 받기에 실패하면 앞 줄은 그대로 두고 단추 위에 오류 줄', (tester) async {
      final server = FakeStatsServer()..matchRequestPageSize = 3;
      await openRequests(tester, server: server);
      server.matchRequestsFailure = 500;

      await tester.ensureVisible(find.widgetWithText(AdminButton, '더 보기'));
      await tester.tap(find.widgetWithText(AdminButton, '더 보기'));
      await tester.pumpAndSettle();

      expect(find.text('더 불러오지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('request-row-r3')), findsOneWidget);
    });

    testWidgets('목록이 비면 "조건에 맞는 신청이 없어요" — 매칭 쌍 목록은 그대로', (tester) async {
      await openRequests(tester, server: FakeStatsServer()..matchRequests = []);

      expect(find.text('조건에 맞는 신청이 없어요'), findsOneWidget);
      expect(key('request-table'), findsNothing);
      expect(key('match-table'), findsOneWidget);
    });

    testWidgets('목록 받는 중 안내 → 끝나면 사라진다', (tester) async {
      final hold = Completer<void>();
      await openMatching(tester, server: FakeStatsServer()..holdMatchRequests = hold, settle: false);
      await tester.pump();
      await tester.pump();

      expect(find.text('신청 목록을 불러오고 있어요'), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text('신청 목록을 불러오고 있어요'), findsNothing);
    });

    testWidgets('목록을 못 받으면 오류 틀 + [다시 시도], 매칭 쌍 목록은 그대로', (tester) async {
      final server = FakeStatsServer()..matchRequestsFailure = 500;
      await openRequests(tester, server: server);

      expect(find.text('신청 목록을 불러오지 못했어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('match-row-m1')), findsOneWidget);
      server.matchRequestsFailure = null;
      await tester.ensureVisible(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('request-row-r1')), findsOneWidget);
    });

    testWidgets('읽기만 한다 — GET 이외를 보내지 않는다', (tester) async {
      final server = await openRequests(tester);

      expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
    });
  });
}
