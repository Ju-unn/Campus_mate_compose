import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/code_input.dart';
import 'package:campus_mate_admin/widgets/gate_card.dart';
import 'package:campus_mate_admin/widgets/side_nav.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/top_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// pen 웹 시안(영역 WOjcG · 보드 UUkLx) 값을 고정한다. 노드 id 는 아직 받지 못해
/// 근거는 대장 전달 값표와 화면 PNG(1440×900) 측정이다.
void main() {
  Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

  // GateCard 는 바탕 페이지까지 그리므로 카드 상자는 그 안의 SelectionArea(카드를 꼭 감싼다)로 잰다.
  Finder cardBox() => find.descendant(of: find.byType(GateCard), matching: find.byType(SelectionArea));

  testWidgets('A0 로그인 카드: 폭 440 · 안쪽 40 · 단추 높이 44', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(session: false));

    final card = rectOf(tester, cardBox());
    expect(card.width, 440);
    expect(card.center, const Offset(720, 450));
    expect(rectOf(tester, find.text('CampusMate')).left, card.left + 40);
    final button = rectOf(tester, find.byType(AdminButton));
    expect(button.height, 44);
    expect(button.width, 440 - 80);
    expect(button.bottom, card.bottom - 40);
  });

  testWidgets('A0 로그인 카드(CRAiQ) 블록 위치: 로고 y40 · 제목 102 · 설명 153 · 단추 219(사이 24)', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(session: false));

    final top = rectOf(tester, cardBox()).top;
    expect(rectOf(tester, find.text('CampusMate')).top - top, 40);
    expect(rectOf(tester, find.text('관리자 로그인')).top - top, 102);
    // 설명은 두 줄(실제 글꼴 · 시험 글꼴 모두)
    expect(rectOf(tester, find.textContaining('운영자 전용')).top - top, 153);
    expect(rectOf(tester, find.byType(AdminButton)).top - top, 219);
  });

  testWidgets('A1 등록 카드 폭 560 · 6칸 52×60 간격 8', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth());

    expect(rectOf(tester, cardBox()).width, 560);
    final first = rectOf(tester, find.byKey(const ValueKey('code-cell-0')));
    final second = rectOf(tester, find.byKey(const ValueKey('code-cell-1')));
    expect(first.size, const Size(52, 60));
    expect(second.left - first.right, 8);
  });

  testWidgets('비밀 키 상자(WKK0m): 안쪽 [12,16] · 키와 복사 사이 12 · 32자는 줄을 바꾸고 복사는 세로 가운데', (tester) async {
    final auth = FakeAdminAuth()
      ..enrollment = const TotpEnrollment(factorId: 'f', secret: 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP');
    await pumpAdminApp(tester, auth: auth);

    final box = rectOf(tester, find.byKey(const ValueKey('secret-box')));
    final secret = rectOf(tester, find.text('JBSW Y3DP EHPK 3PXP JBSW Y3DP EHPK 3PXP'));
    final copy = rectOf(tester, find.widgetWithText(AdminButton, '복사'));
    final decoration = tester.widget<Container>(find.byKey(const ValueKey('secret-box'))).decoration! as BoxDecoration;

    expect(decoration.color, AdminColors.surfaceStrong);
    expect(decoration.borderRadius, BorderRadius.circular(8));
    expect(secret.left - box.left, 16);
    expect(box.right - copy.right, 16);
    expect(secret.top - box.top, 12);
    expect(copy.left - secret.right, 12);
    expect(secret.height, greaterThan(28)); // 한 줄(20/700 · 27)보다 크다 = 줄을 바꿨다
    expect(copy.center.dy, box.center.dy);
  });

  testWidgets('6자리 칸: 지금 칠 칸 web-primary 2 · 나머지 web-outline-strong 1 · 모서리 8 · 글자 20/700', (tester) async {
    final controller = TextEditingController(text: '1');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Material(child: CodeInput(controller: controller, focusNode: focus, onSubmitted: () {}))),
    );
    await tester.pump();

    BoxDecoration cell(int i) => tester
        .widget<Container>(find.descendant(of: find.byKey(ValueKey('code-cell-$i')), matching: find.byType(Container)))
        .decoration! as BoxDecoration;
    final active = cell(1).border! as Border;
    final idle = cell(0).border! as Border;

    expect(active.top, const BorderSide(color: AdminColors.primary, width: 2));
    expect(idle.top, const BorderSide(color: AdminColors.outlineStrong));
    expect(cell(0).borderRadius, BorderRadius.circular(8));
    final digit = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('code-cell-0')), matching: find.byType(Text))).style!;
    expect((digit.fontSize, digit.fontWeight), (20, FontWeight.w700));
  });

  testWidgets('토스트(nmb2y): 높이 44 · 어두운 바탕 · 모서리 8 · 안쪽 16 · 체크 16 + 8 + 글자', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: AdminToast('복사했어요'))));

    final toast = rectOf(tester, find.byType(AdminToast));
    final icon = rectOf(tester, find.byType(Icon));
    final label = rectOf(tester, find.text('복사했어요'));
    final decoration = tester.widget<Container>(find.descendant(of: find.byType(AdminToast), matching: find.byType(Container)).first).decoration! as BoxDecoration;

    expect(toast.height, 44);
    expect(decoration.color, AdminColors.ink);
    expect(decoration.borderRadius, BorderRadius.circular(8));
    expect(icon.left - toast.left, 16);
    expect(icon.size, const Size(16, 16));
    expect(label.left - icon.right, 8);
    expect(toast.right - label.right, 16);
  });

  testWidgets('A1 입력 카드 폭 480 · 권한 없음 카드 폭 480', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: const MfaState(aal2: false, factorId: 'f')));
    expect(rectOf(tester, cardBox()).width, 480);
  });

  testWidgets('셸: SideNav 240 · 항목 208×44(첫 항목 y 96, 간격 4) · TopBar 64 · 제목 x 272', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: const MfaState(aal2: true, factorId: 'f')));

    expect(rectOf(tester, find.byType(SideNav)).width, 240);
    final home = rectOf(tester, find.byKey(const ValueKey('nav-home')));
    final next = rectOf(tester, find.byKey(const ValueKey('nav-heartTasks')));
    expect(home, const Rect.fromLTWH(16, 96, 208, 44));
    expect(next.top - home.bottom, 4);
    final topBar = rectOf(tester, find.byType(TopBar));
    expect(topBar, const Rect.fromLTWH(240, 0, 1200, 64));
    final title = find.descendant(of: find.byType(TopBar), matching: find.text('홈'));
    expect(rectOf(tester, title).left, 272);
  });

  testWidgets('SideNav(O78dY · lJF8t · k5h02V): "관리자" 12/600, 고른 메뉴 글자 14/700 · 나머지 14/600', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: const MfaState(aal2: true, factorId: 'f')));

    TextStyle styleIn(String key, String text) =>
        tester.widget<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text))).style!;
    final sub = tester.widget<Text>(find.descendant(of: find.byType(SideNav), matching: find.text('관리자'))).style!;
    expect((sub.fontSize, sub.fontWeight), (12, FontWeight.w600));
    expect(styleIn('nav-home', '홈').fontWeight, FontWeight.w700);
    expect(styleIn('nav-reports', '신고').fontWeight, FontWeight.w600);
  });

  testWidgets('TopBar "2단계 인증됨" 배지(IKoKe): 점 8 · 왼쪽 10 · 점과 글자 사이 6 · 12/700', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: const MfaState(aal2: true, factorId: 'f')));

    final badge = find.descendant(of: find.byType(TopBar), matching: find.byType(StatusBadge));
    final dot = rectOf(tester, find.descendant(of: badge, matching: find.byKey(const ValueKey('status-badge-dot'))));
    final label = find.descendant(of: badge, matching: find.text('2단계 인증됨'));
    expect(dot.left - rectOf(tester, badge).left, 10);
    expect(rectOf(tester, label).left - dot.right, 6);
    final style = tester.widget<Text>(label).style!;
    expect((style.fontWeight, style.color), (FontWeight.w700, AdminColors.success));
  });

  testWidgets('선택된 메뉴는 primary-wash 바탕, 눌림 효과는 그 칸의 Material 에 그린다', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: const MfaState(aal2: true, factorId: 'f')));

    final item = find.byKey(const ValueKey('nav-home'));
    final ink = find.descendant(of: item, matching: find.byType(InkWell));
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.widget<Material>(material).color, AdminColors.primaryWash);
    expect(tester.getSize(material), tester.getSize(ink));
  });

  testWidgets('단추 4종: 높이 44 · 모서리 8 · 색', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              AdminButton(label: '주', onPressed: () {}),
              AdminButton(label: '보조', variant: AdminButtonVariant.secondary, onPressed: () {}),
              AdminButton(label: '위험', variant: AdminButtonVariant.danger, onPressed: () {}),
              AdminButton(label: '글자', variant: AdminButtonVariant.text, onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    Color? background(String label) {
      final button = tester.widget<TextButton>(find.ancestor(of: find.text(label), matching: find.byType(TextButton)));
      return button.style?.backgroundColor?.resolve(<WidgetState>{});
    }

    for (final label in ['주', '보조', '위험', '글자']) {
      expect(tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(AdminButton))).height, 44);
    }
    expect(background('주'), AdminColors.primary);
    expect(background('보조'), AdminColors.surface);
    expect(background('위험'), AdminColors.danger);
    expect(background('글자'), Colors.transparent);
  });

  testWidgets('요청 중 단추(보드 상태줄): 도는 아이콘 16 + 8 + 글자, 눌리지 않는다', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(home: Material(child: AdminButton(label: '확인', loading: true, onPressed: () => pressed++))),
    );

    await tester.tap(find.byType(AdminButton));
    expect(pressed, 0);
    final loader = rectOf(tester, find.byType(AdminLoader));
    expect(loader.size, const Size(16, 16));
    expect(rectOf(tester, find.text('확인')).left - loader.right, 8);
  });

  testWidgets('A0 실패(pen A0_로그인_실패): 단추 아래 24 에 오류 줄 — 아이콘 16 · 간격 6 · 글자 12 · web-danger', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(session: false), initialPath: '/?error=access_denied');

    final button = rectOf(tester, find.byType(AdminButton));
    const message = '구글 로그인을 마치지 못했어요. 다시 시도해 주세요.';
    final icon = rectOf(tester, find.descendant(of: find.byType(ErrorRow), matching: find.byType(Icon)));
    final text = rectOf(tester, find.text(message));
    expect(icon.top - button.bottom, greaterThanOrEqualTo(24));
    expect(rectOf(tester, find.byType(ErrorRow)).top - button.bottom, 24);
    expect(icon.size, const Size(16, 16));
    expect(text.left - icon.right, 6);
    final style = tester.widget<Text>(find.text(message)).style!;
    expect((style.fontSize, style.color), (12, AdminColors.danger));
    expect(rectOf(tester, cardBox()).bottom - rectOf(tester, find.byType(ErrorRow)).bottom, 40);
  });

  testWidgets('관문 카드 설명 글은 web-body(A0 · A1 입력 · 권한 없음)', (tester) async {
    Color? colorOf(String text) => tester.widget<Text>(find.text(text)).style?.color;

    await pumpAdminApp(tester, auth: FakeAdminAuth(session: false));
    expect(colorOf('운영자 전용 구글 계정으로 로그인해 주세요. 로그인 뒤 2단계 인증이 필요해요.'), AdminColors.body);

    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: const MfaState(aal2: false, factorId: 'f')));
    expect(colorOf('인증 앱에 나온 6자리 숫자를 입력해 주세요.'), AdminColors.body);
  });

  testWidgets('공통 판정 중: 도는 아이콘 16(web-muted) → 12 → 글(sm, web-muted)', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth()..hold = Completer<MfaState>(), settle: false);
    await tester.pump();

    final loader = rectOf(tester, find.byType(AdminLoader));
    final text = rectOf(tester, find.text('로그인 상태를 확인하고 있어요'));
    expect(loader.size, const Size(16, 16));
    expect(text.top - loader.bottom, 12);
    expect(tester.widget<AdminLoader>(find.byType(AdminLoader)).color, AdminColors.muted);
  });
}
