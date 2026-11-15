import 'dart:io';

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/matching/view/paid_card_locked.dart';
import 'package:campus_mate/matching/view/paid_card_purchase_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 결제 확인 팝업(공용 확인 팝업, 대장 전달 2026-11-16)과 하트 부족 시트(pen `x2yPl` 구조 · 지시문 23 D)를 대조한다.
/// 문구는 사용자 확정이 아니라 **초안**이다 — PR 의 "확인 필요 문구" 목록에 같은 글자로 적는다.
Future<void> _loadPretendard() async {
  final loader = FontLoader('Pretendard');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File('assets/fonts/Pretendard-$weight.otf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(_loadPretendard);

  /// 시트를 띄우고 닫혔을 때의 결과를 [result] 에 담는다.
  Future<void> open(
    WidgetTester tester,
    Future<bool> Function(BuildContext) show,
    List<bool> result,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result.add(await show(context)),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  // 열기 확인은 공용 확인 팝업 일반 변형이다(대장 전달 2026-11-16).
  group('결제 확인 팝업', () {
    Future<void> openConfirm(WidgetTester tester, List<bool> result, {int cost = 50}) =>
        open(tester, (context) => showPaidCardConfirmPopup(context, cost: cost), result);

    testWidgets('제목 · 줄인 설명 두 줄(사용자 「문구 너무 많아」 · 「줄바꿈 하기」) · "50 쓰고 열기" · "취소"', (tester) async {
      await openConfirm(tester, []);

      expect(find.byKey(confirmPopupCardKey), findsOneWidget);
      expect(find.text('이 사람을 지금 열어 볼까요?'), findsOneWidget);
      expect(find.text('하트 50개가 차감돼요.\n산 카드는 결정할 때까지 사라지지 않아요.'), findsOneWidget);
      expect(find.textContaining('보유한 하트'), findsNothing);
      expect(find.text('50 쓰고 열기'), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);
    });

    // 하트 글리프 22(대장 전달 pen 값표 2026-11-16) — 카드 자리의 하트(26)는 그대로다.
    testWidgets('확인은 primary 채움이고 라벨 앞에 하트 글리프 22, 라벨과 8', (tester) async {
      await openConfirm(tester, []);

      final confirm = find.widgetWithText(AppButton, '50 쓰고 열기');
      expect(tester.widget<AppButton>(confirm).variant, AppButtonVariant.primary);
      final heart = find.descendant(of: confirm, matching: find.byType(PaidCardHeart));
      expect(tester.getSize(heart), const Size(22, 22));
      expect(tester.getTopLeft(find.text('50 쓰고 열기')).dx - tester.getTopRight(heart).dx, 8);
    });

    testWidgets('숫자는 서버가 준 cost 를 쓴다', (tester) async {
      await openConfirm(tester, [], cost: 80);

      expect(find.text('하트 80개가 차감돼요.\n산 카드는 결정할 때까지 사라지지 않아요.'), findsOneWidget);
      expect(find.text('80 쓰고 열기'), findsOneWidget);
    });

    testWidgets('"50 쓰고 열기" 는 true, "취소" 는 false, 바깥을 누르면 false', (tester) async {
      final result = <bool>[];
      await openConfirm(tester, result);
      await tester.tap(find.text('50 쓰고 열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();

      expect(result, [true, false, false]);
    });
  });

  group('하트 부족 시트', () {
    Future<void> openShort(WidgetTester tester, List<bool> result, {int? balance = 20}) =>
        open(tester, (context) => showPaidCardHeartsShortSheet(context, cost: 50, heartBalance: balance), result);

    testWidgets('제목 "하트가 모자라요"(서버 HEARTS_NOT_ENOUGH 와 같은 글자) · 필요 하트와 보유 하트 · "하트 스토어로 가기" · "닫기"', (tester) async {
      await openShort(tester, []);

      expect(find.text('하트가 모자라요'), findsOneWidget);
      expect(find.text('하트 50개가 필요해요. 지금 보유한 하트는 20개예요.'), findsOneWidget);
      expect(find.text('하트 스토어로 가기'), findsOneWidget);
      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('잔액을 모르면 필요한 하트만 말한다', (tester) async {
      await openShort(tester, [], balance: null);

      expect(find.text('하트 50개가 필요해요.'), findsOneWidget);
    });

    testWidgets('"하트 스토어로 가기" 는 true, "닫기" 는 false', (tester) async {
      final toStore = <bool>[];
      await openShort(tester, toStore);
      await tester.tap(find.text('하트 스토어로 가기'));
      await tester.pumpAndSettle();
      expect(toStore, [true]);

      final closed = <bool>[];
      await openShort(tester, closed);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(closed, [false]);
    });
  });

  testWidgets('글자를 키워도(2.0) 확인 팝업이 넘치지 않고 버튼에 닿을 수 있다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final result = <bool>[];
    await open(tester, (context) => showPaidCardConfirmPopup(context, cost: 50), result);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('50 쓰고 열기'));
    await tester.tap(find.text('50 쓰고 열기'));
    await tester.pumpAndSettle();
    expect(result, [true]);
  });
}
