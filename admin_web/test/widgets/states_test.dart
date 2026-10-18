import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/enter_motion.dart';
import 'package:campus_mate_admin/widgets/gate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// pen 에 없는 상태(호버 · 누름 · 초점 · 비활성 · 움직임)를 웹 토큰 안에서 정한 값으로 고정한다.
void main() {
  ButtonStyle styleOf(WidgetTester tester) => tester.widget<TextButton>(find.byType(TextButton)).style!;

  Future<void> pumpButton(WidgetTester tester, AdminButton button, {bool reduceMotion = false}) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Material(child: Center(child: button)),
        ),
      ),
    );
  }

  group('단추 상태', () {
    testWidgets('초점(키보드)은 web-ink 2 테두리, 올림 6% · 누름 12% ink 덧칠, 물결 없음, 120ms', (tester) async {
      await pumpButton(tester, AdminButton(label: '확인', onPressed: () {}));
      final style = styleOf(tester);

      expect(style.side!.resolve({WidgetState.focused}), const BorderSide(color: AdminColors.ink, width: 2));
      expect(style.overlayColor!.resolve({WidgetState.hovered}), AdminColors.ink.withValues(alpha: 0.06));
      expect(style.backgroundColor!.resolve({WidgetState.pressed}), AdminColors.primaryPressed);
      expect(style.splashFactory, NoSplash.splashFactory);
      expect(style.animationDuration, const Duration(milliseconds: 120));
    });

    testWidgets('보조 단추는 누르면 ink 12% 덧칠, 평소 테두리는 web-outline-strong 1', (tester) async {
      await pumpButton(tester, AdminButton(label: '복사', variant: AdminButtonVariant.secondary, onPressed: () {}));
      final style = styleOf(tester);

      expect(style.side!.resolve(<WidgetState>{}), const BorderSide(color: AdminColors.outlineStrong));
      expect(style.overlayColor!.resolve({WidgetState.pressed}), AdminColors.ink.withValues(alpha: 0.12));
    });

    testWidgets('누를 수 없으면(onPressed 없음) web-surface-strong 바탕 · web-disabled 글자', (tester) async {
      await pumpButton(tester, const AdminButton(label: '확인', onPressed: null));
      final style = styleOf(tester);

      expect(style.backgroundColor!.resolve({WidgetState.disabled}), AdminColors.surfaceStrong);
      expect(style.foregroundColor!.resolve({WidgetState.disabled}), AdminColors.disabled);
    });

    testWidgets('요청 중(loading)은 눌리지 않지만 색은 그대로, 글자도 남는다', (tester) async {
      await pumpButton(tester, AdminButton(label: '확인', loading: true, onPressed: () {}));
      final style = styleOf(tester);

      expect(style.backgroundColor!.resolve({WidgetState.disabled}), AdminColors.primary);
      expect(find.text('확인'), findsOneWidget);
      expect(find.byType(AdminLoader), findsOneWidget);
    });

    testWidgets('글자 단추는 비활성이어도 바탕 없이 글자만 web-disabled', (tester) async {
      await pumpButton(tester, const AdminButton(label: '로그아웃', variant: AdminButtonVariant.text, onPressed: null));
      final style = styleOf(tester);

      expect(style.backgroundColor!.resolve({WidgetState.disabled}), Colors.transparent);
      expect(style.foregroundColor!.resolve({WidgetState.disabled}), AdminColors.disabled);
    });

    testWidgets('동작 줄이기에서는 색 변화도 바로 바꾼다', (tester) async {
      await pumpButton(tester, AdminButton(label: '확인', onPressed: () {}), reduceMotion: true);

      expect(styleOf(tester).animationDuration, Duration.zero);
    });
  });

  testWidgets('왼쪽 메뉴 항목: 키보드 초점이면 web-ink 2 테두리, 물결 없음', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: const MfaState(aal2: true, factorId: 'f')));
    final item = find.byKey(const ValueKey('nav-reports'));
    Material material() => tester.widget<Material>(find.descendant(of: item, matching: find.byType(Material)).first);
    final ink = tester.widget<InkWell>(find.descendant(of: item, matching: find.byType(InkWell)));

    expect(ink.splashFactory, NoSplash.splashFactory);
    expect((material().shape! as RoundedRectangleBorder).side, BorderSide.none);

    Focus.of(tester.element(find.descendant(of: item, matching: find.text('신고')))).requestFocus();
    await tester.pump(); // 초점 바뀜은 다음 차례(microtask)에 알려지고
    await tester.pump(); // 그 setState 가 이 장면에 그려진다

    expect((material().shape! as RoundedRectangleBorder).side, const BorderSide(color: AdminColors.ink, width: 2));
  });

  group('움직임', () {
    Future<void> pumpMotion(WidgetTester tester, {required bool reduceMotion}) {
      return tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: const EnterMotion(child: Text('카드')),
          ),
        ),
      );
    }

    Opacity opacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.ancestor(of: find.text('카드'), matching: find.byType(Opacity)).first);

    testWidgets('관문 카드 등장: 투명 · 8 아래에서 200ms 동안 제자리로', (tester) async {
      await pumpMotion(tester, reduceMotion: false);

      expect(opacity(tester).opacity, 0);
      expect(tester.getTopLeft(find.text('카드')).dy - tester.getTopLeft(find.byType(EnterMotion)).dy, 8);
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(tester).opacity, 1);
      expect(tester.getTopLeft(find.text('카드')).dy, tester.getTopLeft(find.byType(EnterMotion)).dy);
    });

    testWidgets('동작 줄이기에서는 움직임 없이 바로 그린다', (tester) async {
      await pumpMotion(tester, reduceMotion: true);

      expect(find.ancestor(of: find.text('카드'), matching: find.byType(Opacity)), findsNothing);
      expect(tester.getTopLeft(find.text('카드')), tester.getTopLeft(find.byType(EnterMotion)));
    });

    testWidgets('관문 카드는 이 등장을 쓴다', (tester) async {
      await pumpAdminApp(tester, auth: FakeAdminAuth(session: false));

      expect(find.descendant(of: find.byType(GateCard), matching: find.byType(EnterMotion)), findsOneWidget);
    });

    Future<void> showToast(WidgetTester tester, {required bool reduceMotion}) async {
      await tester.pumpWidget(
        MaterialApp(
          // 토스트는 맨 위 Overlay 에 붙으니 동작 줄이기도 그 위(앱 전체)에 건다 — 실제로는 브라우저 설정이 여기로 온다.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => AdminToast.show(context, '복사했어요'), child: const Text('띄우기')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('띄우기'));
      await tester.pump();
    }

    double toastOpacity(WidgetTester tester) => tester
        .widget<FadeTransition>(find.ancestor(of: find.byType(AdminToast), matching: find.byType(FadeTransition)).first)
        .opacity
        .value;

    testWidgets('토스트: 200ms 에 들어오고 2초 뒤 150ms 에 같은 길로 나간다', (tester) async {
      await showToast(tester, reduceMotion: false);

      expect(toastOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(toastOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 1800)); // 2초 — 닫기 시작
      await tester.pump(); // 나가는 움직임의 첫 장면
      await tester.pump(const Duration(milliseconds: 75));
      expect(toastOpacity(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 75)); // 150ms — 다 사라졌다
      expect(toastOpacity(tester), 0);
      // 움직임은 시간이 150ms 를 '넘은' 장면에서 끝난 것으로 친다(브라우저에선 다음 장면, 약 16ms) — 그때 떼어 낸다.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      expect(find.byType(AdminToast), findsNothing);
    });

    testWidgets('토스트: 동작 줄이기에서는 바로 나타나고 바로 사라진다', (tester) async {
      await showToast(tester, reduceMotion: true);

      expect(toastOpacity(tester), 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byType(AdminToast), findsNothing);
    });
  });

  testWidgets('관문 판정 중 화면은 무엇을 기다리는지 글로 알려 준다', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth()..hold = null, settle: false);

    expect(find.text('로그인 상태를 확인하고 있어요'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('제목은 머리글로 읽힌다(A0 제목 · TopBar 제목)', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAdminApp(tester, auth: FakeAdminAuth(session: false));

    expect(tester.getSemantics(find.text('관리자 로그인')), matchesSemantics(label: '관리자 로그인', isHeader: true));
    handle.dispose();
  });

  group('도는 아이콘(요청 중 · 판정 중)', () {
    Future<void> pumpLoader(WidgetTester tester, {required bool reduceMotion}) {
      return tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: const Center(child: AdminLoader(color: AdminColors.muted)),
          ),
        ),
      );
    }

    double turns(WidgetTester tester) => tester
        .widget<RotationTransition>(find.descendant(of: find.byType(AdminLoader), matching: find.byType(RotationTransition)))
        .turns
        .value;

    testWidgets('1초에 한 바퀴 일정하게 돈다', (tester) async {
      await pumpLoader(tester, reduceMotion: false);

      await tester.pump(const Duration(milliseconds: 250));
      expect(turns(tester), closeTo(0.25, 0.001));
    });

    testWidgets('동작 줄이기에서는 멈춘 그림(pen 과 같은 모양)', (tester) async {
      await pumpLoader(tester, reduceMotion: true);

      expect(find.descendant(of: find.byType(AdminLoader), matching: find.byType(RotationTransition)), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
