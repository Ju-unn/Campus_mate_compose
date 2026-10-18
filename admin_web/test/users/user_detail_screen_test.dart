import 'dart:convert';

import 'package:campus_mate_admin/app.dart';
import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/users/user_controller.dart';
import 'package:campus_mate_admin/users/user_item.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/user_fakes.dart';

/// A5 사용자 상세(pen f3jq1) · 대화상자(kFJPd · t1G1R · zcICW · PaxWw) — 값표 B ~ F + PNG A5_* 측정, 대장 결정 3 ~ 7.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');
  const phone = '010-1234-5678';

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<FakeUserServer> openDetail(
    WidgetTester tester, {
    Map<String, Object?>? detail,
    bool settle = true,
  }) async {
    final server = FakeUserServer(users: [userRow('u1')]);
    server.details['u1'] = detail ?? userDetailJson('u1');
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/users/u1', settle: settle);
    return server;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder button(String label) => find.widgetWithText(AdminButton, label);
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;
  Finder dialogBox(String name) => key(name);

  Future<void> letToastGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  group('pen 배치(f3jq1)', () {
    testWidgets('TopBar "사용자 상세", 머리 카드 y96 높이 104: 아바타 자리 56 원 + user 아이콘, 닉네임 20/700 · 배지 둘 · 메타 14 web-muted', (tester) async {
      await openDetail(tester);

      expect(find.text('사용자 상세'), findsOneWidget);
      expect(tester.getRect(key('user-head')), const Rect.fromLTWH(272, 96, 1136, 104));
      expect(tester.getRect(key('user-avatar')), const Rect.fromLTWH(296, 120, 56, 56));
      final avatar = tester.widget<Container>(key('user-avatar'));
      expect((avatar.decoration! as BoxDecoration).color, AdminColors.surfaceStrong);
      expect((avatar.decoration! as BoxDecoration).shape, BoxShape.circle);
      final name = find.text('닉네임A');
      expect(tester.getRect(name).left, 368);
      expect((styleOf(tester, name).fontSize, styleOf(tester, name).fontWeight), (20, FontWeight.w700));
      final badges = tester.widgetList<StatusBadge>(find.descendant(of: key('user-head'), matching: find.byType(StatusBadge))).toList();
      expect([for (final b in badges) (b.label, b.tone)], [('승인', StatusTone.success), ('카카오 로그인', StatusTone.plain)]);
      expect(tester.getSize(find.byWidget(badges.last)).height, 26);
      final meta = find.text('서울대학교 · 가입 2026-09-30 · 마지막 활동 2026-10-18');
      expect(tester.getRect(meta).left, 368);
      expect((styleOf(tester, meta).fontSize, styleOf(tester, meta).color), (14, AdminColors.muted));
    });

    testWidgets('통계 줄 y216: 280×146 카드 셋, 사이 24 — 라벨 14/600 web-muted · 값 32/700', (tester) async {
      await openDetail(tester);

      final labels = ['하트 잔액', '받은 신고', '연락처 차단 개수'];
      for (final (i, label) in labels.indexed) {
        expect(tester.getTopLeft(find.text(label)).dx, 272 + i * 304 + 24, reason: label);
        expect(styleOf(tester, find.text(label)).fontWeight, FontWeight.w600);
        expect(styleOf(tester, find.text(label)).color, AdminColors.muted);
      }
      expect(tester.getSize(find.byType(StatCard).first), const Size(280, 146));
      expect(tester.getTopLeft(find.byType(StatCard).at(1)), const Offset(576, 216));
      expect(tester.getTopLeft(find.text('하트 잔액')).dy, closeTo(216 + 24, 1));
      final value = find.descendant(of: find.byType(StatCard).first, matching: find.text('120'));
      expect((styleOf(tester, value).fontSize, styleOf(tester, value).fontWeight), (32, FontWeight.w700));
      expect(tester.getTopLeft(value).dy, closeTo(216 + 24 + 19 + 12, 1));
      expect(find.descendant(of: find.byType(StatCard).at(1), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: find.byType(StatCard).at(2), matching: find.text('14')), findsOneWidget);
    });

    testWidgets('표 두 칸: 제목 y378 16/700, 원장 표 (272,408) 556×148 · 구매 표 (852,408) 556×148, 머리 12/700 · 줄 52', (tester) async {
      await openDetail(tester);

      expect(tester.getTopLeft(find.text('하트 원장 (최근)')).dy, closeTo(378, 1));
      expect(tester.getTopLeft(find.text('구매 목록')).dx, 852);
      expect(tester.getRect(key('user-ledger')), const Rect.fromLTWH(272, 408, 556, 44 + 52 * 2));
      expect(tester.getRect(key('user-purchases')), const Rect.fromLTWH(852, 408, 556, 44 + 52 * 2));
      // 원장 칸 x: 시각 288 · 종류 438 · 변동 608 · 잔액 698(안쪽 16)
      for (final (text, x) in [('시각', 288.0), ('종류', 438.0), ('변동', 608.0), ('잔액', 698.0)]) {
        expect(tester.getRect(find.descendant(of: key('user-ledger'), matching: find.text(text))).left, x, reason: text);
      }
      for (final (text, x) in [('시각', 868.0), ('상품', 1008.0), ('스토어', 1138.0), ('상태', 1238.0), ('지급 하트', 1328.0)]) {
        expect(tester.getRect(find.descendant(of: key('user-purchases'), matching: find.text(text))).left, x, reason: text);
      }
    });

    testWidgets('원장 줄: 시각 · 종류 · 변동은 부호 그대로(+40 · -30, 색 구분 없음) · 잔액. 구매 줄: 상품 · 스토어 · 상태 글자 · 지급 하트', (tester) async {
      await openDetail(tester);

      final ledger = key('user-ledger');
      for (final text in ['2026-10-18 10:02', '무료 인증샷 보상', '+40', '120', '2026-10-17 21:30', '카드 열기', '-30', '80']) {
        expect(find.descendant(of: ledger, matching: find.text(text)), findsOneWidget, reason: text);
      }
      final minus = find.descendant(of: ledger, matching: find.text('-30'));
      expect(styleOf(tester, minus).color, AdminColors.ink);
      final purchases = key('user-purchases');
      for (final text in ['2026-10-10 18:20', '하트 100개', '구글 플레이', '완료', '100', '2026-09-30 12:05', '하트 50개', '앱스토어', '환불', '50']) {
        expect(find.descendant(of: purchases, matching: find.text(text)), findsOneWidget, reason: text);
      }
    });

    testWidgets('메모 카드 y572 높이 130 · 안쪽 16: "메모" 16/700 + [메모 남기기] 보조(오른쪽, 안쪽 16), 줄 14 web-body "날짜 · admin · 글"', (tester) async {
      await openDetail(tester);

      expect(tester.getRect(key('user-memo')), const Rect.fromLTWH(272, 572, 1136, 130));
      expect(tester.getRect(button('메모 남기기')).right, 1392);
      expect(tester.getRect(button('메모 남기기')).top, 588);
      expect(tester.widget<AdminButton>(button('메모 남기기')).variant, AdminButtonVariant.secondary);
      final line = find.text('2026-10-12 · admin · 결제 문의, 영수증 확인함');
      expect(tester.getTopLeft(line).dx, 288);
      expect(tester.getTopLeft(line).dy, closeTo(650 - 9.5, 1));
      expect((styleOf(tester, line).fontSize, styleOf(tester, line).color), (14, AdminColors.body));
      expect(find.text('2026-10-05 · admin · 정지 문의 접수'), findsOneWidget);
    });

    testWidgets('단추 줄 y718: [하트 조정] 보조 · [정지] 위험 · [탈퇴 대행] 위험 · [전화·카톡 열람] 보조, 사이 8', (tester) async {
      await openDetail(tester);

      final labels = ['하트 조정', '정지', '탈퇴 대행', '전화·카톡 열람'];
      final variants = [AdminButtonVariant.secondary, AdminButtonVariant.danger, AdminButtonVariant.danger, AdminButtonVariant.secondary];
      for (final (i, label) in labels.indexed) {
        expect(tester.widget<AdminButton>(button(label)).variant, variants[i], reason: label);
        expect(tester.getRect(button(label)).top, 718, reason: label);
        expect(tester.getSize(button(label)).height, 44);
      }
      expect(tester.getRect(button('하트 조정')).left, 272);
      expect(tester.getRect(button('정지')).left - tester.getRect(button('하트 조정')).right, 8);
      expect(tester.getRect(button('탈퇴 대행')).left - tester.getRect(button('정지')).right, 8);
      expect(tester.getRect(button('전화·카톡 열람')).left - tester.getRect(button('탈퇴 대행')).right, 8);
    });

    testWidgets('정지 중(A5_사용자_상세_정지중): 배지 "정지" · [정지] 대신 [정지 해제] 보조, [탈퇴 대행] 위험 그대로', (tester) async {
      await openDetail(tester, detail: userDetailJson('u1', status: 'suspended'));

      final badge = tester.widget<StatusBadge>(find.descendant(of: key('user-head'), matching: find.byType(StatusBadge)).first);
      expect((badge.label, badge.tone), ('정지', StatusTone.danger));
      expect(button('정지'), findsNothing);
      expect(tester.widget<AdminButton>(button('정지 해제')).variant, AdminButtonVariant.secondary);
      expect(tester.widget<AdminButton>(button('탈퇴 대행')).variant, AdminButtonVariant.danger);
      // 글자 폭은 렌더 글꼴에 따라 1~4px 달라 절대 x 대신 사이 8 로 잰다
      expect(tester.getRect(button('정지 해제')).left - tester.getRect(button('하트 조정')).right, 8);
      expect(tester.getRect(button('탈퇴 대행')).left - tester.getRect(button('정지 해제')).right, 8);
    });

    testWidgets('탈퇴한 계정(A5_사용자_상세_탈퇴한_계정): 배지 "탈퇴", 단추 줄 대신 "탈퇴한 계정이에요" 12 web-muted (메모 카드 아래 16)', (tester) async {
      await openDetail(tester, detail: userDetailJson('u1', status: 'withdrawn'));

      final badge = tester.widget<StatusBadge>(find.descendant(of: key('user-head'), matching: find.byType(StatusBadge)).first);
      expect((badge.label, badge.tone), ('탈퇴', StatusTone.neutral));
      for (final label in ['하트 조정', '정지', '탈퇴 대행', '전화·카톡 열람']) {
        expect(button(label), findsNothing, reason: label);
      }
      final text = find.text('탈퇴한 계정이에요');
      expect(tester.getTopLeft(text), const Offset(272, 718));
      expect((styleOf(tester, text).fontSize, styleOf(tester, text).color), (12, AdminColors.muted));
      expect(button('메모 남기기'), findsOneWidget);
    });

    testWidgets('기록 없음(A5_사용자_상세_기록없음): 표 대신 "기록이 없어요" 14 web-muted — 원장 · 구매 · 메모 모두, 메모 카드 y443 높이 103', (tester) async {
      await openDetail(tester, detail: userDetailJson('u1', hearts: [], purchases: [], notes: []));

      expect(key('user-ledger'), findsNothing);
      expect(key('user-purchases'), findsNothing);
      expect(find.text('기록이 없어요'), findsNWidgets(3));
      final none = find.text('기록이 없어요').first;
      expect((styleOf(tester, none).fontSize, styleOf(tester, none).color), (14, AdminColors.muted));
      expect(tester.getTopLeft(find.text('하트 원장 (최근)')).dy, closeTo(378, 1));
      expect(tester.getTopLeft(none).dy, closeTo(407.5, 1));
      expect(tester.getRect(key('user-memo')), const Rect.fromLTWH(272, 443, 1136, 103));
      expect(tester.getRect(button('하트 조정')).top, 562);
    });

    testWidgets('로그인 방식이 없으면(서버가 못 알아냄) 로그인 배지만 빠진다', (tester) async {
      await openDetail(tester, detail: userDetailJson('u1', providers: null));

      expect(find.descendant(of: key('user-head'), matching: find.byType(StatusBadge)), findsOneWidget);
      expect(find.textContaining('로그인'), findsNothing);
    });
  });

  group('받는 중 · 못 받음', () {
    testWidgets('없는 사용자(404) → "사용자를 찾을 수 없어요" + [사용자 찾기]', (tester) async {
      final server = FakeUserServer();
      await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/users/nobody');

      expect(find.text('사용자를 찾을 수 없어요'), findsOneWidget);
      await tester.tap(button('사용자 찾기'));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/users');
    });

    testWidgets('서버 오류 → "사용자를 불러오지 못했어요" + [다시 시도]', (tester) async {
      final server = FakeUserServer()..detailFailure = 500;
      server.details['u1'] = userDetailJson('u1');
      await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/users/u1');

      expect(find.text('사용자를 불러오지 못했어요'), findsOneWidget);
      server.detailFailure = null;
      await tester.tap(button('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('닉네임A'), findsWidgets);
    });
  });

  group('하트 조정(kFJPd)', () {
    Future<FakeUserServer> openAdjust(WidgetTester tester) async {
      final server = await openDetail(tester);
      await tester.tap(button('하트 조정'));
      await tester.pumpAndSettle();
      return server;
    }

    Finder amountField() => find.byType(TextField).at(0);
    Finder reasonField() => find.byType(TextField).at(1);
    AdminButton confirm(WidgetTester tester) => tester.widget<AdminButton>(find.descendant(of: dialogBox('heart-dialog'), matching: button('조정')));

    testWidgets('틀: 폭 480 · 높이 464 가운데(y218), 제목 → 설명 → 결제 안내(primary-wash · 60) → 하트 수 칸 44 → 안내 12 → 사유 96 → 단추', (tester) async {
      await openAdjust(tester);

      expect(tester.getRect(dialogBox('heart-dialog')), const Rect.fromLTWH(480, 218, 480, 464));
      expect(tester.getTopLeft(find.text('하트를 조정할까요?')).dy, closeTo(242, 1));
      expect(find.text('닉네임A 의 하트를 더하거나 빼요. 빼면 잔액이 모자랄 때 거절돼요.'), findsOneWidget);
      final notice = key('heart-notice');
      expect(tester.getRect(notice), const Rect.fromLTWH(504, 322, 432, 60));
      expect((tester.widget<Container>(notice).decoration! as BoxDecoration).color, AdminColors.primaryWash);
      final noticeText = find.textContaining('결제 문의라면 먼저 결제 조회로');
      expect(styleOf(tester, noticeText).color, AdminColors.primaryText);
      expect(styleOf(tester, noticeText).fontSize, 12);
      expect(tester.getRect(amountField()), const Rect.fromLTWH(504, 416, 432, 44));
      expect(tester.getTopLeft(find.text('하트 수 (더하면 +, 빼면 -)')).dy, closeTo(394, 1));
      expect(tester.getTopLeft(find.text('한 번에 1,000개까지 더하거나 뺄 수 있어요')).dy, closeTo(472, 1));
      expect(tester.getRect(reasonField()), const Rect.fromLTWH(504, 502, 432, 96));
      expect(tester.getRect(button('조정')).bottom, 658);
      expect(tester.getRect(button('조정')).right, 936);
      expect(tester.getRect(button('조정')).left - tester.getRect(button('취소')).right, 8);
    });

    testWidgets('"+50" 은 자리 글자(web-muted), 안내 "한 번에 1,000개까지…" 는 항상 보인다', (tester) async {
      await openAdjust(tester);

      final hint = find.text('+50');
      expect(hint, findsOneWidget);
      expect(styleOf(tester, hint).color, AdminColors.muted);
      expect(tester.widget<TextField>(amountField()).controller!.text, isEmpty);
      expect(styleOf(tester, find.text('한 번에 1,000개까지 더하거나 뺄 수 있어요')).color, AdminColors.muted);
    });

    testWidgets('칸은 앞의 부호와 숫자만(붙여넣기 포함), 숫자는 여섯 자까지', (tester) async {
      await openAdjust(tester);

      // 한 글자씩 쳐 본다(받아 주지 않는 글자는 칸에 들어가지 않는다)
      for (final (typed, kept) in [('abc', ''), ('+50a', '+50'), ('5-0', '50'), ('+-3', '+3'), ('１２', ''), ('12.5', '125'), ('1234567', '123456')]) {
        await tester.enterText(amountField(), '');
        for (final char in typed.split('')) {
          await tester.enterText(amountField(), tester.widget<TextField>(amountField()).controller!.text + char);
        }
        expect(tester.widget<TextField>(amountField()).controller!.text, kept, reason: typed);
      }
      // 붙여넣기로 통째로 들어오는 틀린 글은 통째로 막힌다(12.5 → 125 처럼 값이 바뀌어 들어가지 않게)
      await tester.enterText(amountField(), '');
      await tester.enterText(amountField(), '12.5');
      expect(tester.widget<TextField>(amountField()).controller!.text, isEmpty);
    });

    testWidgets('0 · 부호만 · ±1000 넘음이면 [조정] 잠김, 1000 · -1000 · +50 은 풀림(사유가 있을 때)', (tester) async {
      await openAdjust(tester);
      await tester.enterText(reasonField(), '결제 오류 정정');

      for (final (typed, ok) in [('', false), ('+', false), ('-', false), ('0', false), ('+0', false), ('1001', false), ('-1001', false), ('1000', true), ('-1000', true), ('+50', true), ('-30', true)]) {
        await tester.enterText(amountField(), typed);
        await tester.pump();
        expect(confirm(tester).onPressed != null, ok, reason: typed);
      }
    });

    testWidgets('사유가 비면(공백뿐 포함) [조정] 잠김', (tester) async {
      await openAdjust(tester);

      await tester.enterText(amountField(), '+50');
      await tester.pump();
      expect(confirm(tester).onPressed, isNull);
      await tester.enterText(reasonField(), '   ');
      await tester.pump();
      expect(confirm(tester).onPressed, isNull);
    });

    testWidgets('[조정] → POST /hearts {amount: 50, reason}, 닫히고 토스트 "하트를 조정했어요" + 상세를 새로 받는다', (tester) async {
      final server = await openAdjust(tester);

      await tester.enterText(amountField(), '+50');
      await tester.enterText(reasonField(), ' 결제 오류 정정 ');
      await tester.pump();
      await tester.tap(button('조정'));
      await tester.pumpAndSettle();

      final post = server.posts('/hearts').single;
      expect(post.url.path, '/admin/users/u1/hearts');
      expect(jsonDecode(post.body), {'amount': 50, 'reason': '결제 오류 정정'});
      expect(find.text('하트를 조정했어요'), findsOneWidget);
      expect(dialogBox('heart-dialog'), findsNothing);
      expect(server.detailFetches('u1'), 2);
      await letToastGo(tester);
    });

    testWidgets('빼기는 부호 그대로(-30)', (tester) async {
      final server = await openAdjust(tester);

      await tester.enterText(amountField(), '-30');
      await tester.enterText(reasonField(), '정정');
      await tester.pump();
      await tester.tap(button('조정'));
      await tester.pumpAndSettle();

      expect(jsonDecode(server.posts('/hearts').single.body), {'amount': -30, 'reason': '정정'});
      await letToastGo(tester);
    });

    testWidgets('잔액 모자람(409 insufficient_hearts) → 대화상자 안 오류 줄 "잔액이 모자라요"(사유 아래 12, 높이 +28), 입력은 그대로', (tester) async {
      final server = await openAdjust(tester);
      server.actionReason = 'insufficient_hearts';

      await tester.enterText(amountField(), '-200');
      await tester.enterText(reasonField(), '결제 오류 정정');
      await tester.pump();
      await tester.tap(button('조정'));
      await tester.pumpAndSettle();

      expect(find.text('잔액이 모자라요'), findsOneWidget);
      expect(find.descendant(of: dialogBox('heart-dialog'), matching: find.byType(ErrorRow)), findsOneWidget);
      expect(tester.getRect(dialogBox('heart-dialog')), const Rect.fromLTWH(480, 204, 480, 492));
      expect(tester.getTopLeft(find.byType(ErrorRow)).dy, closeTo(596, 1));
      expect(tester.widget<TextField>(amountField()).controller!.text, '-200');
      expect(find.text('하트를 조정했어요'), findsNothing);
    });

    testWidgets('서버 오류 → 일반 오류 줄, 처리 중에는 칸 · 취소가 잠기고 Esc 로 닫히지 않는다', (tester) async {
      final server = await openAdjust(tester);
      server.actionFailure = 500;

      await tester.enterText(amountField(), '+5');
      await tester.enterText(reasonField(), '확인');
      await tester.pump();
      await tester.tap(button('조정'));
      await tester.pumpAndSettle();

      expect(find.text('처리하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(dialogBox('heart-dialog'), findsOneWidget);
    });

    testWidgets('[취소] 로 닫으면 아무것도 보내지 않는다', (tester) async {
      final server = await openAdjust(tester);

      await tester.tap(button('취소'));
      await tester.pumpAndSettle();

      expect(dialogBox('heart-dialog'), findsNothing);
      expect(server.writes, isEmpty);
    });
  });

  group('메모(t1G1R)', () {
    testWidgets('틀: 폭 480 · 높이 284 가운데(y308), 설명 · 자리 글자 "메모 내용 (글자 수 제한 있음)", 비면 [저장] 잠김, 500자까지', (tester) async {
      await openDetail(tester);
      await tester.tap(button('메모 남기기').first);
      await tester.pumpAndSettle();

      expect(tester.getRect(key('reason-dialog')), const Rect.fromLTWH(480, 308, 480, 284));
      expect(find.text('메모를 남길까요?'), findsOneWidget);
      expect(find.text('조치 없이 기록만 남겨요. 전화번호·실명을 적지 마세요.'), findsOneWidget);
      expect(find.text('메모 내용 (글자 수 제한 있음)'), findsOneWidget);
      expect(tester.widget<AdminButton>(find.descendant(of: key('reason-dialog'), matching: button('저장'))).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'ㄱ' * 600);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text.length, 500);
    });

    testWidgets('[저장] → POST /notes {text}, 닫히고 메모 목록을 새로 받는다(토스트 없음)', (tester) async {
      final server = await openDetail(tester);
      await tester.tap(button('메모 남기기'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), ' 영수증 다시 확인 ');
      await tester.pump();
      await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('저장')));
      await tester.pumpAndSettle();

      expect(jsonDecode(server.posts('/notes').single.body), {'text': '영수증 다시 확인'});
      expect(key('reason-dialog'), findsNothing);
      expect(server.detailFetches('u1'), 2);
      expect(find.text('처리했어요'), findsNothing);
    });
  });

  group('전화·카톡 열람(zcICW · A5_전화카톡_열람_결과)', () {
    Future<FakeUserServer> openView(WidgetTester tester, {Map<String, Object?>? private}) async {
      final server = await openDetail(tester);
      if (private != null) server.private = private;
      await tester.tap(button('전화·카톡 열람'));
      await tester.pumpAndSettle();
      return server;
    }

    Future<void> submitReason(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), '문의 응대');
      await tester.pump();
      await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('열람')));
      await tester.pumpAndSettle();
    }

    testWidgets('사유 대화상자: 설명 "그 자리에서만 보여 주고…", 자리 "사유 (필수)", 비면 [열람] 잠김', (tester) async {
      await openView(tester);

      expect(find.text('전화·카톡을 열람할까요?'), findsOneWidget);
      expect(find.text("그 자리에서만 보여 주고 저장하지 않아요. 작업 기록에 '열람'만 남아요."), findsOneWidget);
      expect(find.text('사유 (필수)'), findsOneWidget);
      expect(tester.widget<AdminButton>(find.descendant(of: key('reason-dialog'), matching: button('열람'))).onPressed, isNull);
    });

    testWidgets('열람하면 같은 자리에서 결과로 바뀐다: 제목 "전화·카톡", 값 16/700 web-ink(선택해서 복사 가능), 안내 12 web-muted, [닫기] 주 — 요청은 POST /private {reason}', (tester) async {
      final server = await openView(tester);

      await submitReason(tester);

      expect(jsonDecode(server.posts('/private').single.body), {'reason': '문의 응대'});
      expect(find.text('전화·카톡'), findsOneWidget);
      expect(key('reason-dialog'), findsNothing);
      final dialog = key('private-dialog');
      expect(tester.getSize(dialog).width, 480);
      expect(tester.getSize(dialog).height, closeTo(281, 1));
      final value = find.byWidgetPredicate((w) => w is SelectableText && w.data == phone);
      expect(value, findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == 'kakao_id_a'), findsOneWidget);
      final style = tester.widget<SelectableText>(value).style!;
      expect((style.fontSize, style.fontWeight, style.color), (16, FontWeight.w700, AdminColors.ink));
      expect(find.text('전화번호'), findsOneWidget);
      expect(find.text('카카오톡 아이디'), findsOneWidget);
      expect(find.text('창을 닫으면 지워져요. 다시 보려면 다시 열람해야 하고 기록이 한 번 더 남아요.'), findsOneWidget);
      expect(tester.widget<AdminButton>(button('닫기')).variant, AdminButtonVariant.primary);
    });

    testWidgets('값이 없으면 "없음" web-muted', (tester) async {
      await openView(tester, private: {'phone_number': null, 'kakao_id': 'k'});

      await submitReason(tester);

      final none = find.byWidgetPredicate((w) => w is SelectableText && w.data == '없음');
      expect(none, findsOneWidget);
      expect(tester.widget<SelectableText>(none).style!.color, AdminColors.muted);
    });

    testWidgets('닫으면 값이 화면 · provider 상태 어디에도 남지 않는다(전역 provider · 캐시 금지)', (tester) async {
      await openView(tester);
      await submitReason(tester);
      expect(find.text(phone, findRichText: true), findsOneWidget);

      await tester.tap(button('닫기'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining('010-', findRichText: true), findsNothing);
      expect(find.textContaining('kakao_id_a', findRichText: true), findsNothing);
      final container = ProviderScope.containerOf(tester.element(find.byType(AdminApp)));
      final stateText = '${container.read(userDetailProvider('u1'))} ${container.read(userSearchProvider)}';
      expect(stateText, isNot(contains('010-')));
      expect(stateText, isNot(contains('kakao_id_a')));
      expect(const PrivateContact(phoneNumber: phone, kakaoId: 'kakao_id_a').toString(), isNot(contains('010')));
      // 다시 보려면 다시 열람해야 한다 — 새 요청 한 번 더
      await tester.tap(button('전화·카톡 열람'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      await submitReason(tester);
      expect(find.text('전화·카톡'), findsOneWidget);
    });

    testWidgets('열람 → 닫기 뒤, 어떤 provider 도 전화 · 카톡 값(또는 열람 결과 객체)을 만든 적도 들고 있은 적도 없다', (tester) async {
      final recorder = _Recorder();
      final server = FakeUserServer(users: [userRow('u1')]);
      server.details['u1'] = userDetailJson('u1');
      await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/users/u1', observers: [recorder]);
      await tester.tap(button('전화·카톡 열람'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '문의 응대');
      await tester.pump();
      await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('열람')));
      await tester.pumpAndSettle();
      expect(find.text('전화·카톡'), findsOneWidget); // 값이 대화상자에 실제로 떴다
      await tester.tap(button('닫기'));
      await tester.pumpAndSettle();

      expect(recorder.seen, isNotEmpty); // 관찰이 실제로 일했다
      expect(recorder.seen.any((v) => v is PrivateContact), isFalse);
      final text = recorder.seen.map((v) => '$v').join('\n');
      expect(text, isNot(contains(phone)));
      expect(text, isNot(contains('kakao_id_a')));
      final container = ProviderScope.containerOf(tester.element(find.byType(AdminApp)));
      final now = '${container.read(userDetailProvider('u1'))} ${container.read(userSearchProvider)}';
      expect(now, isNot(contains(phone)));
    });

    testWidgets('탈퇴 계정(409 account_withdrawn) → 사유 대화상자 안 오류 줄 "탈퇴한 계정은 열람할 수 없어요"', (tester) async {
      final server = await openView(tester);
      server.actionReason = 'account_withdrawn';

      await submitReason(tester);

      expect(find.text('탈퇴한 계정은 열람할 수 없어요'), findsOneWidget);
      expect(key('reason-dialog'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('서버 오류 → 일반 오류 줄, 값은 나오지 않는다', (tester) async {
      final server = await openView(tester);
      server.actionFailure = 500;

      await submitReason(tester);

      expect(find.text('처리하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });
  });

  group('탈퇴 대행(PaxWw)', () {
    Future<FakeUserServer> openClose(WidgetTester tester, {Map<String, Object?>? detail}) async {
      final server = await openDetail(tester, detail: detail);
      await tester.tap(button('탈퇴 대행'));
      await tester.pumpAndSettle();
      return server;
    }

    Finder verifiedField() => find.byType(TextField).at(0);
    Finder reasonField() => find.byType(TextField).at(1);
    Finder confirmButton() => find.descendant(of: dialogBox('close-dialog'), matching: button('탈퇴 대행'));

    testWidgets('정지 아님: 폭 480 · 높이 495 가운데(y202), 본인 확인 3줄 + 애플 안내 + 칸 둘, 정지 경고는 없다', (tester) async {
      await openClose(tester);

      expect(tester.getSize(dialogBox('close-dialog')).height, closeTo(495, 1));
      expect(tester.getTopLeft(dialogBox('close-dialog')).dx, 480);
      expect(find.text('탈퇴를 대행할까요?'), findsOneWidget);
      expect(find.text('되돌릴 수 없어요. 본인 확인을 마친 뒤에만 실행해요.'), findsOneWidget);
      final identity = key('close-identity');
      expect((tester.widget<Container>(identity).decoration! as BoxDecoration).color, AdminColors.canvas);
      expect(tester.getSize(identity).height, closeTo(121, 1));
      final title = find.text('본인 확인 (요청과 맞는지 확인해 주세요)');
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (12, FontWeight.w700));
      for (final line in ['로그인 방식: 카카오', '학교 메일: 요청과 맞는지 직접 확인', '닉네임: 닉네임A 와 일치']) {
        expect(find.text(line), findsOneWidget, reason: line);
        expect(styleOf(tester, find.text(line)).color, AdminColors.ink);
      }
      expect(find.byIcon(Icons.check_box), findsNothing);
      expect(key('close-suspended'), findsNothing);
      expect(find.text('애플 철회와 전체 로그아웃은 본인 토큰이 필요해서 대행할 수 없어요.'), findsOneWidget);
      expect(find.text('어떻게 확인했나요 (필수)'), findsOneWidget);
      expect(find.text('예: 가입 메일로 답장을 받아 확인했어요'), findsOneWidget);
      expect(find.text('사유 (필수)'), findsOneWidget);
      expect(find.text('사유를 적어 주세요'), findsOneWidget);
      expect(tester.getSize(verifiedField()).height, 44);
      expect(tester.getSize(reasonField()).height, 44);
      expect(tester.widget<AdminButton>(confirmButton()).variant, AdminButtonVariant.danger);
    });

    testWidgets('정지 중: 정지 경고 줄(warning-wash · 66)이 더해져 높이 573', (tester) async {
      await openClose(tester, detail: userDetailJson('u1', status: 'suspended'));

      expect(tester.getSize(dialogBox('close-dialog')).height, closeTo(573, 1));
      final warning = key('close-suspended');
      expect((tester.widget<Container>(warning).decoration! as BoxDecoration).color, AdminColors.warningWash);
      expect(tester.getSize(warning).height, closeTo(66, 1));
      final text = find.text('정지 중인 계정이에요. 탈퇴시키면 같은 학교 메일 재가입이 기간 없이 막혀요.');
      expect(styleOf(tester, text).color, AdminColors.warning);
    });

    testWidgets('둘 다 차야 [탈퇴 대행] 이 풀린다(공백뿐은 빈 것)', (tester) async {
      await openClose(tester);

      expect(tester.widget<AdminButton>(confirmButton()).onPressed, isNull);
      await tester.enterText(verifiedField(), '가입 메일로 답장 확인');
      await tester.pump();
      expect(tester.widget<AdminButton>(confirmButton()).onPressed, isNull);
      await tester.enterText(reasonField(), '   ');
      await tester.pump();
      expect(tester.widget<AdminButton>(confirmButton()).onPressed, isNull);
      await tester.enterText(reasonField(), '본인 탈퇴 요청');
      await tester.pump();
      expect(tester.widget<AdminButton>(confirmButton()).onPressed, isNotNull);
    });

    testWidgets('확인 방법에 "@" 가 있으면 잠기고 칸 아래 12 danger "메일 주소는 적지 마세요(기록에 남아요)"(정지 아님 495 + 12 + 18)', (tester) async {
      await openClose(tester);

      await tester.enterText(reasonField(), '본인 탈퇴 요청');
      await tester.enterText(verifiedField(), 'gina@school.ac.kr 로 확인했어요');
      await tester.pump();

      expect(tester.widget<AdminButton>(confirmButton()).onPressed, isNull);
      final warning = find.text('메일 주소는 적지 마세요(기록에 남아요)');
      expect(styleOf(tester, warning).color, AdminColors.danger);
      expect(styleOf(tester, warning).fontSize, 12);
      expect(tester.getTopLeft(warning).dy, closeTo(tester.getBottomLeft(verifiedField()).dy + 12, 1));
      expect(tester.getSize(dialogBox('close-dialog')).height, closeTo(525, 1)); // 정지 경고(78)가 있으면 pen 의 603
      await tester.enterText(verifiedField(), '가입 메일로 답장 확인');
      await tester.pump();
      expect(find.text('메일 주소는 적지 마세요(기록에 남아요)'), findsNothing);
      expect(tester.widget<AdminButton>(confirmButton()).onPressed, isNotNull);
    });

    testWidgets('확인 방법은 200자까지(서버 상한)', (tester) async {
      await openClose(tester);

      await tester.enterText(verifiedField(), 'ㄱ' * 300);

      expect(tester.widget<TextField>(verifiedField()).controller!.text.length, 200);
    });

    testWidgets('실행 → POST /close-account {reason, verified_by}, 닫히고 토스트 "탈퇴를 대행했어요", 상세를 새로 받아 "탈퇴한 계정이에요"가 보인다', (tester) async {
      final server = await openClose(tester);

      await tester.enterText(verifiedField(), '가입 메일로 답장을 받아 확인했어요');
      await tester.enterText(reasonField(), '본인 탈퇴 요청');
      await tester.pump();
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(jsonDecode(server.posts('/close-account').single.body), {'reason': '본인 탈퇴 요청', 'verified_by': '가입 메일로 답장을 받아 확인했어요'});
      expect(find.text('탈퇴를 대행했어요'), findsOneWidget);
      expect(dialogBox('close-dialog'), findsNothing);
      expect(key('user-banner'), findsNothing);
      expect(find.text('탈퇴한 계정이에요'), findsOneWidget);
      expect(button('탈퇴 대행'), findsNothing);
      expect(server.detailFetches('u1'), 2);
      await letToastGo(tester);
    });

    testWidgets('바깥 정리 실패(카카오 끊기) → 토스트 + 화면 위 경고 띠 "카카오 연결 끊기를 마치지 못했어요 — 작업 기록 확인"(머리 카드 위 16)', (tester) async {
      final server = await openClose(tester);
      server.close = {
        ...server.close,
        'cleanup': {'push_tokens': 'ok', 'student_id_files': 'ok', 'kakao_unlink': 'failed'},
      };

      await tester.enterText(verifiedField(), '답장 확인');
      await tester.enterText(reasonField(), '본인 탈퇴 요청');
      await tester.pump();
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(find.text('탈퇴를 대행했어요'), findsOneWidget);
      final banner = key('user-banner');
      expect(find.descendant(of: banner, matching: find.text('카카오 연결 끊기를 마치지 못했어요 — 작업 기록 확인')), findsOneWidget);
      expect((tester.widget<Container>(banner).decoration! as BoxDecoration).color, AdminColors.warningWash);
      expect(tester.getTopLeft(banner).dy, 96);
      expect(tester.getTopLeft(key('user-head')).dy, tester.getBottomLeft(banner).dy + 16);
      await letToastGo(tester);
    });

    testWidgets('푸시 · 인증 파일 정리만 실패하면 일반 문구의 경고 띠', (tester) async {
      final server = await openClose(tester);
      server.close = {
        ...server.close,
        'cleanup': {'push_tokens': 'failed', 'student_id_files': 'ok', 'kakao_unlink': 'skipped'},
      };

      await tester.enterText(verifiedField(), '답장 확인');
      await tester.enterText(reasonField(), '본인 탈퇴 요청');
      await tester.pump();
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(find.text('탈퇴 뒤 정리를 일부 마치지 못했어요 — 작업 기록 확인'), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('이미 탈퇴(409 account_withdrawn) → 오류 줄 "이미 탈퇴한 계정이에요"', (tester) async {
      final server = await openClose(tester);
      server.actionReason = 'account_withdrawn';

      await tester.enterText(verifiedField(), '답장 확인');
      await tester.enterText(reasonField(), '본인 탈퇴 요청');
      await tester.pump();
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(find.text('이미 탈퇴한 계정이에요'), findsOneWidget);
      expect(dialogBox('close-dialog'), findsOneWidget);
    });

    testWidgets('서버 오류 → 일반 오류 줄, 입력은 그대로', (tester) async {
      final server = await openClose(tester);
      server.actionFailure = 500;

      await tester.enterText(verifiedField(), '답장 확인');
      await tester.enterText(reasonField(), '본인 탈퇴 요청');
      await tester.pump();
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(find.text('처리하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(tester.widget<TextField>(verifiedField()).controller!.text, '답장 확인');
    });
  });

  group('정지 · 정지 해제(D2 경로)', () {
    testWidgets('[정지] → 사유 대화상자(W2 와 같은 것) → POST /admin/profiles/u1/suspend, 토스트 "처리했어요", 새로 받으면 [정지 해제]', (tester) async {
      final server = await openDetail(tester);

      await tester.tap(button('정지'));
      await tester.pumpAndSettle();
      expect(find.text('사용자를 정지할까요?'), findsOneWidget);
      expect(find.text('닉네임A 를 정지해요. 작업 기록에 사유가 남고, 사유는 필수예요.'), findsOneWidget);
      expect(tester.widget<AdminButton>(find.descendant(of: key('reason-dialog'), matching: button('정지'))).variant, AdminButtonVariant.danger);
      await tester.enterText(find.byType(TextField), '반복 신고');
      await tester.pump();
      await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('정지')));
      await tester.pumpAndSettle();

      expect(server.writes.single, '/admin/profiles/u1/suspend {"reason":"반복 신고"}');
      expect(find.text('처리했어요'), findsOneWidget);
      expect(button('정지 해제'), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('[정지 해제] → POST /unsuspend', (tester) async {
      final server = await openDetail(tester, detail: userDetailJson('u1', status: 'suspended'));

      await tester.tap(button('정지 해제'));
      await tester.pumpAndSettle();
      expect(find.text('정지를 해제할까요?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '소명 확인');
      await tester.pump();
      await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('정지 해제')));
      await tester.pumpAndSettle();

      expect(server.writes.single, '/admin/profiles/u1/unsuspend {"reason":"소명 확인"}');
      expect(button('정지'), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('다른 관리자가 먼저(409 already_done) → "이미 처리된 항목이에요" 대화상자 + 상세를 새로 받는다', (tester) async {
      final server = await openDetail(tester);
      server.actionReason = 'already_done';

      await tester.tap(button('정지'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '반복 신고');
      await tester.pump();
      await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('정지')));
      await tester.pumpAndSettle();

      expect(find.text('이미 처리된 항목이에요'), findsOneWidget);
      expect(server.detailFetches('u1'), 2);
    });
  });

  group('큰 글자 · 낮은 창 · 동작 줄이기', () {
    testWidgets('글자 1.3배 + 1280×800: 상세 · 하트 조정 · 탈퇴 대행(정지 중, 가장 긴 대화상자)이 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = FakeUserServer(users: [userRow('u1')]);
      server.details['u1'] = userDetailJson('u1', status: 'suspended');
      await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/users/u1', size: const Size(1280, 800));
      expect(tester.takeException(), isNull);

      await tester.tap(button('하트 조정'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(button('취소'));
      await tester.pumpAndSettle();
      await tester.tap(button('탈퇴 대행'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 화면보다 길면 90% 까지만 늘고 안이 스크롤된다
      expect(tester.getSize(dialogBox('close-dialog')).height, lessThanOrEqualTo(800 * 0.9));
    });

    testWidgets('낮은 창(1280×560): 탈퇴 대행 대화상자는 화면 90% 에서 멈추고 단추까지 스크롤로 닿는다', (tester) async {
      final server = FakeUserServer(users: [userRow('u1')]);
      server.details['u1'] = userDetailJson('u1', status: 'suspended');
      await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/users/u1', size: const Size(1280, 560));

      await tester.ensureVisible(button('탈퇴 대행')); // 낮은 창은 화면이 스크롤된다
      await tester.pumpAndSettle();
      await tester.tap(button('탈퇴 대행'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(dialogBox('close-dialog')).height, closeTo(560 * 0.9, 1));
      await tester.ensureVisible(find.descendant(of: dialogBox('close-dialog'), matching: button('취소')));
      await tester.pump();
      expect(tester.getRect(find.descendant(of: dialogBox('close-dialog'), matching: button('취소'))).bottom, lessThanOrEqualTo(560));
    });

    testWidgets('동작 줄이기: 열람 결과가 움직임 없이 바뀐다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openDetail(tester);
      await tester.tap(button('전화·카톡 열람'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '문의 응대');
      await tester.pump();

      await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('열람')));
      await tester.pump();
      await tester.pump();

      // 교차 없이 바로 결과 하나만
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
      expect(key('private-dialog'), findsOneWidget);
      expect(key('reason-dialog'), findsNothing);
    });
  });
}

/// 모든 provider 가 만들고 바꾼 값을 모은다(열람 값이 어디에도 오르지 않았는지 훑는 용도)
final class _Recorder extends ProviderObserver {
  final List<Object?> seen = [];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) => seen.add(value);

  @override
  void didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue) => seen.add(newValue);
}
