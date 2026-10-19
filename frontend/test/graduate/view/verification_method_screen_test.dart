import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';
import 'package:campus_mate/graduate/view/verification_method_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/view/pretendard.dart';
import 'gate_screen_harness.dart';

/// pen 02-0 인증 방법 고르기 `M1L5Yg`(값표 §1). 카드 `vegg1` · `m4Gcfg`(마스터 `sPWwm` Card · Outline).
void main() {
  late GateHarness harness;

  setUpAll(loadPretendard);
  setUp(() => harness = GateHarness());

  const schoolTitle = '학교 메일로 인증';
  const graduateTitle = '졸업증명서로 인증';
  const schoolBody = '재학생 · 학교 메일이 있는 분. 메일로 받은 코드로 바로 확인해요.';
  const graduateBody = '졸업해서 학교 메일이 없는 분. 졸업증명서로 확인해요. 확인에 시간이 걸릴 수 있어요.';

  Finder card(String title) => find.ancestor(of: find.text(title), matching: find.byType(InkWell));
  Finder cardMaterial(String title) => find.ancestor(of: card(title), matching: find.byType(Material)).first;
  RoundedRectangleBorder shapeOf(WidgetTester tester, String title) =>
      tester.widget<Material>(cardMaterial(title)).shape! as RoundedRectangleBorder;
  ElevatedButton nextButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '다음'));

  Future<void> pump(WidgetTester tester, {double textScale = 1, bool disableAnimations = false}) =>
      harness.pump(tester, const VerificationMethodScreen(), textScale: textScale, disableAnimations: disableAnimations);

  group('문구 · 구성 (값표 §1)', () {
    testWidgets('제목 · 설명 · 카드 둘 · [다음] · 로그아웃이 pen 문구 그대로 있다', (tester) async {
      await pump(tester);

      expect(find.text('인증 방법을 골라 주세요'), findsOneWidget);
      expect(find.text('가입하려면 학교 인증이 필요해요.'), findsOneWidget);
      expect(find.text(schoolTitle), findsOneWidget);
      expect(find.text(schoolBody), findsOneWidget);
      expect(find.text(graduateTitle), findsOneWidget);
      expect(find.text(graduateBody), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
      expect(find.text('로그아웃'), findsOneWidget);
    });

    testWidgets('앱바와 뒤로가기 화살표가 없다 (pen `EHHg3` Leading · 제목 꺼짐, 뒤로가기 없음)', (tester) async {
      await pump(tester);

      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip(onboardingBackLabel), findsNothing);
    });
  });

  group('글자 · 색 · 치수 (값표 §1)', () {
    testWidgets('제목 `Sziar` 24/700 ink · 설명 `dh9X5` 16/normal body, 둘 다 왼쪽 24', (tester) async {
      await pump(tester);

      final title = styleOf(tester, '인증 방법을 골라 주세요');
      expect((title.fontSize, title.fontWeight, title.color), (24.0, FontWeight.w700, AppColors.ink));
      final body = styleOf(tester, '가입하려면 학교 인증이 필요해요.');
      expect((body.fontSize, body.color), (16.0, AppColors.body));
      expect(tester.getTopLeft(find.text('인증 방법을 골라 주세요')).dx, 24);
      expect(tester.getTopLeft(find.text('가입하려면 학교 인증이 필요해요.')).dx, 24);
    });

    testWidgets('세로 위치: 제목 위 56(앱바 자리) · 카드1 위 142.67 (PNG 실측 ÷1.5)', (tester) async {
      await pump(tester);

      expect(tester.getTopLeft(find.text('인증 방법을 골라 주세요')).dy, closeTo(56, 0.5));
      expect(tester.getTopLeft(cardMaterial(schoolTitle)).dy, closeTo(142.67, 1.5));
    });

    testWidgets('카드 제목 16/600 ink · 설명 14 muted (`eE104` · `w5usmG`)', (tester) async {
      await pump(tester);

      final title = styleOf(tester, schoolTitle);
      expect((title.fontSize, title.fontWeight, title.color), (16.0, FontWeight.w600, AppColors.ink));
      final body = styleOf(tester, schoolBody);
      expect((body.fontSize, body.color), (14.0, AppColors.muted));
    });

    testWidgets('카드: 폭 312 · 안쪽 20 · 모서리 16 · 바탕 흰색 · 테두리 hairline 1, 둘 사이 12', (tester) async {
      await pump(tester);

      final first = cardMaterial(schoolTitle);
      expect(tester.getSize(first).width, 312);
      expect(shapeOf(tester, schoolTitle).borderRadius, BorderRadius.circular(16));
      expect(shapeOf(tester, schoolTitle).side, const BorderSide(color: AppColors.hairline));
      expect(tester.widget<Material>(first).color, AppColors.canvas);
      // 안쪽 20(테두리 안쪽 선): 카드 왼쪽 24 + 20 = 44 에서 제목이 시작한다(PNG 제목 왼쪽 67÷1.5 ≈ 44.7).
      expect(tester.getTopLeft(find.text(schoolTitle)).dx, 24 + 20);
      expect(tester.getSize(first).height, 118, reason: 'PNG 실측 카드 높이 118 = 20+22+12+44+20');
      final gap = tester.getTopLeft(cardMaterial(graduateTitle)).dy - tester.getBottomLeft(first).dy;
      expect(gap, 12);
    });

    testWidgets('[다음] 폭 312 · 높이 52, 로그아웃 높이 48, 로그아웃 아래 16 · 둘 사이 4', (tester) async {
      await pump(tester);

      final next = find.widgetWithText(ElevatedButton, '다음');
      expect(tester.getSize(next), const Size(312, 52));
      final logout = find.ancestor(of: find.text('로그아웃'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(logout).height, 48);
      expect(tester.getBottomLeft(logout).dy, 780 - 16);
      expect(tester.getTopLeft(logout).dy - tester.getBottomLeft(next).dy, 4);
    });
  });

  group('선택 (값표 §1: 선택됨 = 테두리 primary 1, 라디오 표시 없음)', () {
    testWidgets('처음에는 카드 둘 다 hairline 테두리, [다음] 은 꺼져 있다', (tester) async {
      await pump(tester);

      for (final title in [schoolTitle, graduateTitle]) {
        expect(shapeOf(tester, title).side.color, AppColors.hairline);
      }
      expect(nextButton(tester).onPressed, isNull);
    });

    testWidgets('카드를 누르면 그 카드만 primary 테두리가 되고 [다음] 이 켜진다 — 서버는 부르지 않는다', (tester) async {
      await pump(tester);

      await tester.tap(card(graduateTitle));
      await tester.pump();

      expect(shapeOf(tester, graduateTitle).side, const BorderSide(color: AppColors.primary));
      expect(shapeOf(tester, schoolTitle).side.color, AppColors.hairline);
      expect(nextButton(tester).onPressed, isNotNull);
      expect(harness.repository.chosen, isEmpty);
    });

    testWidgets('선택된 카드 오른쪽 위에만 circle-check 20 primary 가 있다(안쪽 오른쪽 20 · 위 20)', (tester) async {
      await pump(tester);
      Finder mark(String title) => find.descendant(of: cardMaterial(title), matching: find.byIcon(AppIcons.circleCheck));
      expect(find.byIcon(AppIcons.circleCheck), findsNothing);

      await tester.tap(card(graduateTitle));
      await tester.pump();

      expect(mark(schoolTitle), findsNothing);
      expect(mark(graduateTitle), findsOneWidget);
      final icon = tester.widget<Icon>(mark(graduateTitle));
      expect((icon.size, icon.color), (20.0, AppColors.primary));
      final cardRect = tester.getRect(cardMaterial(graduateTitle));
      final iconRect = tester.getRect(mark(graduateTitle));
      expect(cardRect.right - iconRect.right, 20);
      expect(iconRect.top - cardRect.top, 20);

      await tester.tap(card(schoolTitle));
      await tester.pump();
      expect(mark(schoolTitle), findsOneWidget);
      expect(mark(graduateTitle), findsNothing);
    });

    testWidgets('글자 2배에서도 선택 표식이 제목과 겹치지 않는다', (tester) async {
      await pump(tester, textScale: 2);
      await tester.tap(card(graduateTitle));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final icon = tester.getRect(find.byIcon(AppIcons.circleCheck));
      expect(tester.getRect(find.text(graduateTitle)).right, lessThanOrEqualTo(icon.left));
    });

    testWidgets('다른 카드를 누르면 선택이 옮겨 간다', (tester) async {
      await pump(tester);

      await tester.tap(card(graduateTitle));
      await tester.pump();
      await tester.tap(card(schoolTitle));
      await tester.pump();

      expect(shapeOf(tester, schoolTitle).side.color, AppColors.primary);
      expect(shapeOf(tester, graduateTitle).side.color, AppColors.hairline);
    });

    testWidgets('[다음] 은 고른 방법을 서버에 한 번 보낸다', (tester) async {
      await pump(tester);

      await tester.tap(card(graduateTitle));
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();

      expect(harness.repository.chosen, [VerificationMethod.graduateCertificate]);
    });

    testWidgets('낭독: 카드는 버튼이고 고른 카드는 선택됨으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      await tester.tap(card(schoolTitle));
      await tester.pump();

      final selected = tester.getSemantics(find.bySemanticsLabel(RegExp('^$schoolTitle')));
      final unselected = tester.getSemantics(find.bySemanticsLabel(RegExp('^$graduateTitle')));
      expect(selected.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      expect(selected.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(unselected.getSemanticsData().flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });
  });

  group('보내는 중 · 실패 (값표 §7)', () {
    testWidgets('보내는 중에는 [다음] 에 도는 표시가 있고 카드를 바꾸지 못하며 연타해도 한 번만 나간다', (tester) async {
      harness.repository.holdChoose = Completer<void>();
      await pump(tester);
      await tester.tap(card(graduateTitle));
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.tap(card(schoolTitle));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(harness.repository.chosen, hasLength(1));
      expect(shapeOf(tester, graduateTitle).side.color, AppColors.primary, reason: '보내는 중에는 선택이 그대로다');
      harness.repository.holdChoose!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('실패하면 토스트로 알리고 고른 카드를 그대로 둔다', (tester) async {
      harness.repository.chooseResult = const FailureResult(NetworkFailure());
      await pump(tester);
      await tester.tap(card(schoolTitle));
      await tester.pump();

      await tester.tap(find.text('다음'));
      await tester.pump();
      await tester.pump();

      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      expect(shapeOf(tester, schoolTitle).side.color, AppColors.primary);
      expect(nextButton(tester).onPressed, isNotNull);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('글자 확대 · 터치 영역 · 동작 줄이기', () {
    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 $scale배에서 넘침 예외가 없고 카드가 화면 폭 안이다', (tester) async {
        await pump(tester, textScale: scale);

        expect(tester.takeException(), isNull);
        final rect = tester.getRect(cardMaterial(graduateTitle));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
      });
    }

    testWidgets('글자 2배에서 로그아웃까지 스크롤로 닿는다', (tester) async {
      await pump(tester, textScale: 2);

      await tester.scrollUntilVisible(find.text('로그아웃'), 200, scrollable: find.byType(Scrollable).first);

      expect(find.text('로그아웃'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('누르는 칸은 모두 높이 44 이상이다(카드 · [다음] · 로그아웃)', (tester) async {
      await pump(tester);

      for (final finder in [
        card(schoolTitle),
        card(graduateTitle),
        find.widgetWithText(ElevatedButton, '다음'),
        find.ancestor(of: find.text('로그아웃'), matching: find.byType(InkWell)).first,
      ]) {
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('동작 줄이기를 켜도 pumpAndSettle 이 끝난다', (tester) async {
      await pump(tester, disableAnimations: true);

      await tester.tap(card(schoolTitle));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('카드 눌림 효과는 화면 전체가 아니라 카드 크기 Material 위에 그려진다(COMMON §4-2)', (tester) async {
      await pump(tester);

      expect(tester.getSize(cardMaterial(schoolTitle)), tester.getSize(card(schoolTitle)));
    });
  });
}
