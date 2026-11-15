import 'dart:async';

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_dialog_route.dart';
import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 공용 확인 팝업(pen "Row X · 확인 팝업" — 일반 `v14xI` · 위험 `xCdlQ` · 설명 없음 `BDVsY`, 대장 전달 값표 2026-11-16).
void main() {
  const title = '채팅방을 나갈까요?';
  const body = '나가면 이 대화를 다시 볼 수 없어요.';
  const confirm = '나가기';

  final card = find.byKey(confirmPopupCardKey);
  // 처리 중에는 라벨 자리에 도는 표시가 들어가 글자로 찾지 못한다 — 라벨 값으로 찾는다.
  Finder button(String label) => find.byWidgetPredicate((widget) => widget is AppButton && widget.label == label);

  bool? result;

  Future<void> open(
    WidgetTester tester, {
    String? withBody = body,
    bool danger = false,
    Widget? confirmLeading,
    Future<void> Function()? onConfirm,
    Size screen = const Size(360, 780),
    String confirmLabel = confirm,
  }) async {
    result = null;
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showConfirmPopup(
                context,
                title: title,
                body: withBody,
                confirmLabel: confirmLabel,
                danger: danger,
                confirmLeading: confirmLeading,
                onConfirm: onConfirm,
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  // 검토 지적(2026-11-16): 팝업이 열리면 낭독기가 제목을 창 이름으로 읽는다.
  testWidgets('카드는 낭독기에 하나의 창(경로)이고 이름은 제목이다', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(
      tester.getSemantics(find.byKey(confirmPopupCardKey)),
      isSemantics(label: title, scopesRoute: true, namesRoute: true),
    );
    semantics.dispose();
  });

  group('일반(v14xI)', () {
    testWidgets('카드 320 · 가운데 · 흰 바탕 · 모서리 24 · 팝업 그림자, 뒤는 모달 딤', (tester) async {
      await open(tester);

      final rect = tester.getRect(card);
      expect(rect.width, 320);
      expect(rect.center.dx, 180);
      expect(rect.center.dy, closeTo(390, 0.5));
      final box = tester.widget<Container>(card).decoration! as BoxDecoration;
      expect(box.color, AppColors.canvas);
      expect(box.borderRadius, BorderRadius.circular(AppRadius.lg));
      expect(box.boxShadow, AppElevation.popup);
      final barrier = tester.widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier).last);
      expect(barrier.color.value, AppColors.scrim);
      // 살짝 커지며 나온다(움직임은 공용 팝업 경로).
      expect(find.ancestor(of: card, matching: find.byType(PopupMotion)), findsOneWidget);
    });

    testWidgets('제목 20/700 ink 1.5 · 자간 -0.4, 설명 16/400 body 1.5 — 둘 다 가운데 정렬', (tester) async {
      await open(tester);

      final titleText = tester.widget<Text>(find.text(title));
      final t = titleText.style!;
      expect((t.fontSize, t.fontWeight, t.color, t.height, t.letterSpacing), (20, FontWeight.w700, AppColors.ink, 1.5, -0.4));
      expect(titleText.textAlign, TextAlign.center);
      final bodyText = tester.widget<Text>(find.text(body));
      final b = bodyText.style!;
      expect((b.fontSize, b.fontWeight, b.color, b.height), (16, FontWeight.w400, AppColors.body, 1.5));
      expect(bodyText.textAlign, TextAlign.center);
    });

    testWidgets('위 24 · 좌우 20 · 아래 20, 제목 → 12 → 설명 → 20 → 버튼 줄(같은 폭 · 사이 8 · 52)', (tester) async {
      await open(tester);

      final rect = tester.getRect(card);
      final titleRect = tester.getRect(find.text(title));
      final bodyRect = tester.getRect(find.text(body));
      final cancel = tester.getRect(button('취소'));
      final ok = tester.getRect(button(confirm));
      expect(titleRect.top - rect.top, 24);
      expect(bodyRect.top - titleRect.bottom, 12);
      expect(cancel.top - bodyRect.bottom, 20);
      expect(rect.bottom - cancel.bottom, 20);
      expect(cancel.left - rect.left, 20);
      expect(rect.right - ok.right, 20);
      expect(ok.left - cancel.right, 8);
      expect(cancel.size, const Size(136, 52));
      expect(ok.size, const Size(136, 52));
    });

    testWidgets('왼쪽 취소는 회색 채움(tonal), 오른쪽 확인은 primary 채움', (tester) async {
      await open(tester);

      expect(tester.widget<AppButton>(button('취소')).variant, AppButtonVariant.tonal);
      expect(tester.widget<AppButton>(button(confirm)).variant, AppButtonVariant.primary);
    });

    testWidgets('확인 앞 그림을 주면 버튼 라벨 앞에 붙는다(유료 카드 하트)', (tester) async {
      await open(tester, confirmLeading: const SizedBox(key: ValueKey('heart'), width: 22, height: 22));

      expect(find.descendant(of: button(confirm), matching: find.byKey(const ValueKey('heart'))), findsOneWidget);
    });
  });

  testWidgets('위험(xCdlQ) — 확인은 error 채움 · 흰 글자', (tester) async {
    await open(tester, danger: true);

    expect(tester.widget<AppButton>(button(confirm)).variant, AppButtonVariant.dangerStrong);
  });

  testWidgets('설명 없음(BDVsY, 로그아웃) — 제목 20/700 가운데, 위 24 · 제목 → 버튼 20 · 높이 146', (tester) async {
    await open(tester, withBody: null);

    final rect = tester.getRect(card);
    final titleRect = tester.getRect(find.text(title));
    final cancel = tester.getRect(button('취소'));
    expect(tester.widget<Text>(find.text(title)).style!.fontSize, 20);
    expect(tester.widget<Text>(find.text(title)).textAlign, TextAlign.center);
    expect(titleRect.top - rect.top, 24);
    expect(cancel.top - titleRect.bottom, 20);
    expect(rect.height, 146);
  });

  // pen 에 큰 글자 상태가 없다 — 반쪽 버튼(52 고정)에 라벨이 한 줄로 안 들어가면 잘리지 않게 세로로 쌓는다(DESIGN §11.2).
  testWidgets('글자 2배라 반쪽 버튼에 라벨이 안 들어가면 확인 위 · 취소 아래로 쌓고(사이 8) 글자가 잘리지 않는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, confirmLabel: '정말 영구 삭제');

    expect(tester.takeException(), isNull);
    final cancel = tester.getRect(button('취소'));
    final ok = tester.getRect(button('정말 영구 삭제'));
    expect(cancel.top - ok.bottom, 8);
    expect(ok.width, 280);
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: card, matching: find.byType(RichText)))) {
      expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5),
          reason: paragraph.text.toPlainText());
    }
  });

  testWidgets('글자 2배라도 짧은 라벨이 반쪽에 들어가면 그대로 나란히 둔다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);

    expect(tester.getRect(button(confirm)).left - tester.getRect(button('취소')).right, 8);
  });

  testWidgets('좁은 화면에서는 좌우 20 을 두고 줄어든다', (tester) async {
    await open(tester, screen: const Size(320, 640));

    final rect = tester.getRect(card);
    expect(rect.left, 20);
    expect(rect.width, 280);
  });

  group('결과', () {
    testWidgets('확인은 true', (tester) async {
      await open(tester);
      await tester.tap(button(confirm));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(card, findsNothing);
    });

    testWidgets('취소는 false', (tester) async {
      await open(tester);
      await tester.tap(button('취소'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('바깥을 누르면 false', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(card, findsNothing);
    });
  });

  group('처리 중(onConfirm) — 사용자 「빨간 버튼 + 돌아가는 표시」', () {
    late Completer<void> hold;
    late int calls;

    Future<void> openHeld(WidgetTester tester, {bool danger = false}) async {
      hold = Completer<void>();
      calls = 0;
      await open(tester, danger: danger, onConfirm: () {
        calls++;
        return hold.future;
      });
      await tester.tap(button(confirm));
      await tester.pump();
    }

    testWidgets('확인은 색 그대로 흰 도는 표시(20)로 바뀌고 다시 눌리지 않는다 · 취소는 회색 그대로 눌린다', (tester) async {
      await openHeld(tester, danger: true);

      final ok = tester.widget<AppButton>(button(confirm));
      expect(ok.isLoading, isTrue);
      final elevated = tester.widget<ElevatedButton>(find.descendant(of: button(confirm), matching: find.byType(ElevatedButton)));
      expect(elevated.style!.backgroundColor!.resolve({WidgetState.disabled}), AppColors.error);
      final spinner = find.descendant(of: button(confirm), matching: find.byType(CircularProgressIndicator));
      expect(tester.getSize(spinner), const Size(20, 20));
      expect(tester.widget<CircularProgressIndicator>(spinner).color, AppColors.onPrimary);
      expect(tester.widget<AppButton>(button('취소')).onPressed, isNotNull);
      expect(tester.widget<AppButton>(button('취소')).variant, AppButtonVariant.tonal);

      await tester.tap(button(confirm), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);

      hold.complete();
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(result, isTrue);
    });

    testWidgets('기다리는 중에 취소로 닫아도 일은 그대로 끝나고, 밑 화면은 닫히지 않는다', (tester) async {
      await openHeld(tester);

      await tester.tap(button('취소'));
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(result, isFalse);

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text('열기'), findsOneWidget);
    });
  });
}
