import 'dart:io';

import 'package:campus_mate/matching/view/paid_card_purchase_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 결제 확인 시트(pen `x2yPl` 구조, 값표 §8)와 하트 부족 시트(지시문 23 D)를 대조한다.
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

  group('결제 확인 시트', () {
    Future<void> openConfirm(WidgetTester tester, List<bool> result, {int? balance = 320, int cost = 50}) =>
        open(tester, (context) => showPaidCardConfirmSheet(context, cost: cost, heartBalance: balance), result);

    testWidgets('초안 문구 — 제목 · 설명 · "50 쓰고 열기" · "취소" (옛 "한 명 더 소개받을까요?" 는 없다)', (tester) async {
      await openConfirm(tester, []);

      expect(find.text('이 사람을 지금 열어 볼까요?'), findsOneWidget);
      expect(
        find.text('하트 50개가 차감돼요. 지금 보유한 하트는 320개예요. 한 번에 한 명만 열 수 있고, 산 카드는 결정할 때까지 사라지지 않아요.'),
        findsOneWidget,
      );
      expect(find.text('50 쓰고 열기'), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);
      expect(find.text('한 명 더 소개받을까요?'), findsNothing);
      expect(find.text('50 쓰고 소개받기'), findsNothing);
    });

    testWidgets('pen `x2yPl` — 제목 20/700 #222222, 설명 16/400/1.5 #3F3F3F, 시트 위 모서리 24 · 좌우 20', (tester) async {
      await openConfirm(tester, []);

      final title = tester.widget<Text>(find.text('이 사람을 지금 열어 볼까요?')).style!;
      expect(title.fontSize, 20);
      expect(title.fontWeight, FontWeight.w700);
      expect(title.color, const Color(0xFF222222));
      final description = tester.widget<Text>(find.textContaining('하트 50개가 차감돼요')).style!;
      expect(description.fontSize, 16);
      expect(description.height, 1.5);
      expect(description.color, const Color(0xFF3F3F3F));
      expect(tester.getTopLeft(find.text('이 사람을 지금 열어 볼까요?')).dx, 20);
    });

    testWidgets('주 버튼 `PAa2x` 320×52 모서리 8 #FF385C, 하트 26 + 간격 8 + 18/700 흰 글자', (tester) async {
      await openConfirm(tester, []);

      final button = find.ancestor(of: find.text('50 쓰고 열기'), matching: find.byType(Material)).first;
      expect(tester.getSize(button), const Size(320, 52));
      final material = tester.widget<Material>(button);
      expect(material.color, const Color(0xFFFF385C));
      expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(8));
      final style = tester.widget<Text>(find.text('50 쓰고 열기')).style!;
      expect(style.fontSize, 18);
      expect(style.fontWeight, FontWeight.w700);
      final heart = find.descendant(of: button, matching: find.byType(Image));
      expect(tester.getSize(heart), const Size(26, 26));
      expect(tester.getRect(find.text('50 쓰고 열기')).left - tester.getRect(heart).right, 8);
    });

    testWidgets('숫자는 서버가 준 cost 를 쓴다', (tester) async {
      await openConfirm(tester, [], cost: 70);

      expect(find.text('70 쓰고 열기'), findsOneWidget);
      expect(find.textContaining('하트 70개가 차감돼요'), findsOneWidget);
    });

    testWidgets('잔액을 모르면(읽는 중 · 실패) 잔액 문장만 뺀다 — 틀린 숫자를 쓰지 않는다', (tester) async {
      await openConfirm(tester, [], balance: null);

      expect(find.textContaining('지금 보유한 하트'), findsNothing);
      expect(find.text('하트 50개가 차감돼요. 한 번에 한 명만 열 수 있고, 산 카드는 결정할 때까지 사라지지 않아요.'), findsOneWidget);
    });

    testWidgets('"50 쓰고 열기" 는 true, "취소" 는 false, 바깥을 누르면 false', (tester) async {
      final confirmed = <bool>[];
      await openConfirm(tester, confirmed);
      await tester.tap(find.text('50 쓰고 열기'));
      await tester.pumpAndSettle();
      expect(confirmed, [true]);

      final cancelled = <bool>[];
      await openConfirm(tester, cancelled);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(cancelled, [false]);

      final dismissed = <bool>[];
      await openConfirm(tester, dismissed);
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();
      expect(dismissed, [false]);
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

  testWidgets('글자를 키워도(2.0) 확인 시트가 넘치지 않고 버튼에 닿을 수 있다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final result = <bool>[];
    await open(tester, (context) => showPaidCardConfirmSheet(context, cost: 50, heartBalance: 320), result);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('50 쓰고 열기'));
    await tester.tap(find.text('50 쓰고 열기'));
    await tester.pumpAndSettle();
    expect(result, [true]);
  });
}
