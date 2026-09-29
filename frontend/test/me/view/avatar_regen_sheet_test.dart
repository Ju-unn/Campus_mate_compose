import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/me/view/avatar_regen_sheet.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _heartAsset = 'assets/images/heart-flat-vector-on-primary-v1.png';

void main() {
  AvatarRegenChoice? choice;
  late bool closed;

  setUp(() {
    choice = null;
    closed = false;
  });

  /// pen 보드와 같은 360×780 화면에서 시트를 연다.
  Future<void> open(WidgetTester tester, {required int cost, required int balance, double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                choice = await showAvatarRegenSheet(context, cost: cost, heartBalance: balance);
                closed = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Finder cta(String label) => find.widgetWithText(SafetySheetButton, label);

  group('15b 하트로 만들기(pen aGaPA)', () {
    testWidgets('제목 · 설명에 서버 숫자(비용 10 · 잔액 320) · 하트 CTA · 취소', (tester) async {
      await open(tester, cost: 10, balance: 320);

      expect(find.text('아바타를 다시 만들까요?'), findsOneWidget);
      expect(
        find.text('하트 10개가 차감돼요. 지금 보유한 하트는 320개예요. 새 아바타는 바로 프로필에 반영돼요.'),
        findsOneWidget,
      );
      expect(cta('10 쓰고 만들기'), findsOneWidget);
      expect(cta('취소'), findsOneWidget);
    });

    testWidgets('숫자는 앱 상수가 아니라 넘겨받은 값이다', (tester) async {
      await open(tester, cost: 20, balance: 45);

      expect(find.text('하트 20개가 차감돼요. 지금 보유한 하트는 45개예요. 새 아바타는 바로 프로필에 반영돼요.'), findsOneWidget);
      expect(cta('20 쓰고 만들기'), findsOneWidget);
    });

    testWidgets('pen 값 — 제목 20/700 ink 렌더 29 · 설명 16/400 body lh1.5 · 시트 틀 SafetySheet', (tester) async {
      await open(tester, cost: 10, balance: 320);

      final sheet = tester.getRect(find.byType(SafetySheet));
      expect(sheet.width, 360);
      // 위 여백 12 + 손잡이 4 + 간격 16.
      expect(tester.getTopLeft(find.text('아바타를 다시 만들까요?')).dy - sheet.top, 32);
      expect(tester.getSize(find.text('아바타를 다시 만들까요?')).height, 29);

      final title = tester.widget<Text>(find.text('아바타를 다시 만들까요?'));
      expect(title.style!.fontSize, 20);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(title.style!.color, AppColors.ink);

      final description = tester.widget<Text>(find.textContaining('차감돼요'));
      expect(description.style!.fontSize, 16);
      expect(description.style!.fontWeight, FontWeight.w400);
      expect(description.style!.color, AppColors.body);
      expect(description.style!.height, 1.5);

      // 제목 → 설명 16(`Fgqkt` → `Ra0he`).
      expect(
        tester.getTopLeft(find.textContaining('차감돼요')).dy - tester.getBottomLeft(find.text('아바타를 다시 만들까요?')).dy,
        16,
      );
    });

    testWidgets('pen 값 — 설명 아래 36 · CTA 320×52 주색 · 하트 26×26 과 글자 사이 8 · 취소 16 아래 회색', (tester) async {
      await open(tester, cost: 10, balance: 320);

      final primary = cta('10 쓰고 만들기');
      final cancel = cta('취소');
      // 16 + 투명 4(`RAC9j`) + 16.
      expect(tester.getTopLeft(primary).dy - tester.getBottomLeft(find.textContaining('차감돼요')).dy, 36);
      expect(tester.getSize(primary), const Size(320, 52));
      expect(tester.getSize(cancel), const Size(320, 52));
      expect(tester.getTopLeft(cancel).dy - tester.getBottomLeft(primary).dy, 16);

      Material materialOf(Finder button) =>
          tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first);
      expect(materialOf(primary).color, AppColors.primary);
      expect(materialOf(cancel).color, AppColors.surfaceStrong);

      final heart = find.descendant(of: primary, matching: find.byType(Image));
      expect(tester.getSize(heart), const Size(26, 26));
      expect(tester.getTopLeft(find.text('10 쓰고 만들기')).dx - tester.getTopRight(heart).dx, 8);
    });

    testWidgets('하트는 on-primary 재화 그림(pen n3D3iC)이다', (tester) async {
      await open(tester, cost: 10, balance: 320);

      final image = tester.widget<Image>(find.descendant(of: cta('10 쓰고 만들기'), matching: find.byType(Image)));
      expect((image.image as AssetImage).assetName, _heartAsset);
    });

    testWidgets('하트 그림은 화면 읽기에서 빠진다 — 버튼 밖 따로 멈추지 않고, 단위는 설명이 읽어 준다', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, cost: 10, balance: 320);

      expect(find.bySemanticsLabel('하트'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('하트 10개가 차감돼요')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('만들기를 누르면 regenerate 를 돌려주고 닫힌다', (tester) async {
      await open(tester, cost: 10, balance: 320);

      await tester.tap(cta('10 쓰고 만들기'));
      await tester.pumpAndSettle();

      expect(choice, AvatarRegenChoice.regenerate);
      expect(find.byType(SafetySheet), findsNothing);
    });
  });

  group('15b-2 무료(pen N5lXcc)', () {
    testWidgets('무료 설명 · 하트 없는 "무료로 만들기"', (tester) async {
      await open(tester, cost: 0, balance: 320);

      expect(find.text('아바타를 다시 만들까요?'), findsOneWidget);
      expect(find.text('첫 번째 다시 만들기는 무료예요. 새 아바타는 바로 프로필에 반영돼요.'), findsOneWidget);
      expect(cta('무료로 만들기'), findsOneWidget);
      expect(find.descendant(of: find.byType(SafetySheet), matching: find.byType(Image)), findsNothing);
      expect(tester.getSize(cta('무료로 만들기')), const Size(320, 52));
    });

    testWidgets('잔액이 0 이어도 무료 차례면 무료 모양이다', (tester) async {
      await open(tester, cost: 0, balance: 0);

      expect(cta('무료로 만들기'), findsOneWidget);
    });

    testWidgets('무료로 만들기를 누르면 regenerate', (tester) async {
      await open(tester, cost: 0, balance: 320);

      await tester.tap(cta('무료로 만들기'));
      await tester.pumpAndSettle();

      expect(choice, AvatarRegenChoice.regenerate);
    });
  });

  group('15b-3 하트 모자람(pen i8rkW)', () {
    testWidgets('제목 "하트가 모자라요"(C8) · 설명에 서버 숫자(10 · 3) · 하트 + "하트 충전하기"', (tester) async {
      await open(tester, cost: 10, balance: 3);

      expect(find.text('하트가 모자라요'), findsOneWidget);
      expect(find.text('하트 10개가 필요해요. 지금 보유한 하트는 3개예요.'), findsOneWidget);
      expect(cta('하트 충전하기'), findsOneWidget);
      expect(find.text('아바타를 다시 만들까요?'), findsNothing);

      final heart = find.descendant(of: cta('하트 충전하기'), matching: find.byType(Image));
      expect(tester.getSize(heart), const Size(26, 26));
      expect((tester.widget<Image>(heart).image as AssetImage).assetName, _heartAsset);
    });

    testWidgets('잔액이 비용과 같으면 모자라지 않다', (tester) async {
      await open(tester, cost: 10, balance: 10);

      expect(cta('10 쓰고 만들기'), findsOneWidget);
    });

    testWidgets('하트 충전하기를 누르면 chargeHearts', (tester) async {
      await open(tester, cost: 10, balance: 3);

      await tester.tap(cta('하트 충전하기'));
      await tester.pumpAndSettle();

      expect(choice, AvatarRegenChoice.chargeHearts);
    });

    testWidgets('글자가 "하트 충전하기" 라 하트 그림은 화면 읽기에서 뺀다 — "하트 하트" 로 두 번 읽지 않는다', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, cost: 10, balance: 3);

      expect(find.bySemanticsLabel('하트'), findsNothing);
      handle.dispose();
    });
  });

  testWidgets('취소를 누르면 null', (tester) async {
    await open(tester, cost: 10, balance: 320);

    await tester.tap(cta('취소'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(choice, isNull);
  });

  testWidgets('바깥을 누르면 null', (tester) async {
    await open(tester, cost: 10, balance: 320);

    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(choice, isNull);
  });

  testWidgets('눌림 효과는 버튼 안의 Material 에 그린다(COMMON §4-2)', (tester) async {
    await open(tester, cost: 10, balance: 320);

    for (final label in ['10 쓰고 만들기', '취소']) {
      final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), const Size(320, 52), reason: label);
    }
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 넘치거나 잘리는 글자가 없다.
  const shapes = {'15b': (10, 320), '15b-2': (0, 320), '15b-3': (10, 3)};
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    for (final MapEntry(key: name, value: (cost, balance)) in shapes.entries) {
      testWidgets('$name 글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
        await open(tester, cost: cost, balance: balance, scale: scale);

        expect(tester.takeException(), isNull);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
            find.descendant(of: find.byType(SafetySheet), matching: find.byType(RichText)))) {
          final text = paragraph.text.toPlainText();
          // 폭은 배치 때 받은 최대 폭으로 잰다 — size.width 로 재면 소수점 오차로 한 줄이 두 줄로 세어진다.
          expect(paragraph.getMaxIntrinsicHeight(paragraph.constraints.maxWidth),
              lessThanOrEqualTo(paragraph.size.height + 0.5),
              reason: text);
          expect(paragraph.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(paragraph.size.width + 0.5),
              reason: text);
        }
      });
    }
  }
}
