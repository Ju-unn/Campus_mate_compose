import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../matching/model/fake_card_repository.dart';
import '../model/fake_account_repository.dart';

void main() {
  late FakeCardRepository cards;
  late FakeAccountRepository account;
  late ProviderContainer container;

  /// 설정 화면 대신 버튼 하나로 16c 를 연다. pen 프레임과 같은 360×780.
  Future<void> openSheets(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    cards = FakeCardRepository();
    account = FakeAccountRepository();
    container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(cards),
        accountRepositoryProvider.overrideWithValue(account),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(onPressed: () => showWithdrawSheets(context), child: const Text('열기')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Future<void> openFinalSheet(WidgetTester tester) async {
    await openSheets(tester);
    await tester.tap(find.text('영구 삭제'));
    await tester.pumpAndSettle();
  }

  Finder inFirst(Finder finder) => find.descendant(of: find.byType(WithdrawFirstSheet), matching: finder);
  Finder inFinal(Finder finder) => find.descendant(of: find.byType(WithdrawFinalSheet), matching: finder);
  ElevatedButton deleteButton(WidgetTester tester) => tester.widget<ElevatedButton>(
        find.ancestor(of: find.text('정말 영구 삭제'), matching: find.byType(ElevatedButton)),
      );

  group('1차 시트(pen t4KbA)', () {
    testWidgets('값표 6-1 글자를 보여준다', (tester) async {
      await openSheets(tester);

      for (final text in [
        '정말 떠나시나요?',
        '탈퇴보다 먼저 매칭을 잠시 쉬어볼 수 있어요.',
        '매칭만 잠시 멈추기',
        '프로필과 대화는 그대로 유지돼요.',
        '일시중지',
        '탈퇴하면 아래 내용이 삭제돼요',
        '프로필과 인증 정보',
        '수락 매칭 기록',
        '모든 대화 내용',
        '삭제한 내용은 되돌릴 수 없고, 재가입은 2개월 뒤에 가능해요.',
        '영구 삭제',
        '취소',
      ]) {
        expect(inFirst(find.text(text)), findsOneWidget, reason: text);
      }
      for (final icon in [AppIcons.userRound, AppIcons.heart, AppIcons.messageCircle]) {
        expect(inFirst(find.byIcon(icon)), findsOneWidget);
      }
    });

    testWidgets('요소 사이 간격 14(pen t4KbA gap)', (tester) async {
      await openSheets(tester);

      final heading = inFirst(find.text('탈퇴하면 아래 내용이 삭제돼요'));
      final items = find.ancestor(
        of: inFirst(find.text('프로필과 인증 정보')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && (widget.decoration as BoxDecoration?)?.color == AppColors.surfaceSoft,
        ),
      );
      expect(tester.getRect(items).top - tester.getRect(heading).bottom, 14);
    });

    testWidgets('슬픈 마스코트 88(pen ycFq3)', (tester) async {
      await openSheets(tester);

      final mascot = inFirst(find.byType(Image));
      expect((tester.widget<Image>(mascot).image as AssetImage).assetName, 'assets/images/mascot-female-sad.png');
      expect(tester.getSize(mascot), const Size(88, 88));
    });

    testWidgets('first sheet pause button pauses matching and closes the sheet', (tester) async {
      await openSheets(tester);

      await tester.tap(find.text('일시중지'));
      await tester.pumpAndSettle();

      expect(cards.pausedValue, isTrue);
      expect(find.byType(WithdrawFirstSheet), findsNothing);
      expect(find.byType(WithdrawFinalSheet), findsNothing);
    });

    testWidgets('일시중지의 눌림 효과는 그 버튼 안에 그려진다(COMMON §4-2)', (tester) async {
      await openSheets(tester);

      final material = find.ancestor(of: find.text('일시중지'), matching: find.byType(Material)).first;
      final ink = find.ancestor(of: find.text('일시중지'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(material), tester.getSize(ink));
      expect(tester.getSize(material).height, 48);
    });

    testWidgets('first sheet 영구 삭제 opens the final sheet', (tester) async {
      await openFinalSheet(tester);

      expect(find.byType(WithdrawFirstSheet), findsNothing);
      expect(find.byType(WithdrawFinalSheet), findsOneWidget);
      expect(account.withdrawCalls, 0);
    });

    testWidgets('영구 삭제는 error 채움 AppButton(dangerStrong) 이다', (tester) async {
      await openSheets(tester);

      final button = tester.widget<AppButton>(inFirst(find.byType(AppButton)));
      expect(button.label, '영구 삭제');
      expect(button.variant, AppButtonVariant.dangerStrong);
    });

    testWidgets('취소는 아무것도 하지 않고 닫는다', (tester) async {
      await openSheets(tester);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(WithdrawFirstSheet), findsNothing);
      expect(find.byType(WithdrawFinalSheet), findsNothing);
      expect(cards.pausedValue, isNull);
      expect(tester.getSize(find.text('열기')), isNot(Size.zero));
    });
  });

  group('최종 시트(pen s7M9MC)', () {
    testWidgets('값표 6-2 글자와 경고 배지(errorWash, 대장 결정 1)', (tester) async {
      await openFinalSheet(tester);

      for (final text in [
        '정말 삭제할까요?',
        '프로필, 매칭 기록, 대화를 모두 영구적으로 삭제합니다. 이 작업은 취소할 수 없어요.',
        '재가입은 탈퇴 후 2개월이 지나야 가능해요.',
        '정말 영구 삭제',
        '취소',
      ]) {
        expect(inFinal(find.text(text)), findsOneWidget, reason: text);
      }
      final badge = find.ancestor(
        of: find.text('재가입은 탈퇴 후 2개월이 지나야 가능해요.'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && (widget.decoration as BoxDecoration?)?.color == AppColors.errorWash,
        ),
      );
      expect(badge, findsOneWidget);
      expect(find.descendant(of: badge, matching: find.byIcon(AppIcons.alertTriangle)), findsOneWidget);
    });

    testWidgets('final sheet → "정말 영구 삭제" calls withdraw once, button disabled while submitting', (tester) async {
      await openFinalSheet(tester);
      account.holdWithdraw = Completer<void>();

      await tester.tap(find.text('정말 영구 삭제'));
      await tester.pump();

      expect(deleteButton(tester).enabled, isFalse);
      await tester.tap(find.text('정말 영구 삭제'), warnIfMissed: false);
      account.holdWithdraw!.complete();
      await tester.pumpAndSettle();

      expect(account.withdrawCalls, 1);
      // 로그아웃은 main.dart 리스너 한 곳이 한다 — 시트는 상태만 바꾼다.
      expect(container.read(accountStatusListenableProvider).value, AccountStatus.withdrawn);
    });

    testWidgets('실패하면 문구를 보여주고 다시 누를 수 있다', (tester) async {
      await openFinalSheet(tester);
      account.withdrawResult = const FailureResult(NetworkFailure());

      await tester.tap(find.text('정말 영구 삭제'));
      await tester.pumpAndSettle();

      expect(inFinal(find.text('네트워크 연결을 확인해 주세요')), findsOneWidget);
      expect(deleteButton(tester).enabled, isTrue);
      expect(container.read(accountStatusListenableProvider).value, AccountStatus.active);
    });

    testWidgets('취소는 탈퇴를 부르지 않고 닫는다', (tester) async {
      await openFinalSheet(tester);

      await tester.tap(inFinal(find.text('취소')));
      await tester.pumpAndSettle();

      expect(find.byType(WithdrawFinalSheet), findsNothing);
      expect(account.withdrawCalls, 0);
    });
  });

  // DESIGN §11.2 — 시스템 글꼴 확대. 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다.
  group('글자 확대', () {
    List<String> clippedTexts() => [
          for (final element in find.byType(RichText).evaluate())
            if (element.renderObject case final RenderParagraph p
                when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5)
              p.text.toPlainText(),
        ];

    for (final scale in [1.3, 1.5, 2.0]) {
      testWidgets('배율 $scale 에서 두 시트 모두 넘치거나 잘리는 글자가 없다', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openSheets(tester);

        expect(tester.takeException(), isNull);
        expect(clippedTexts(), isEmpty);

        await tester.ensureVisible(find.text('영구 삭제'));
        await tester.tap(find.text('영구 삭제'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(clippedTexts(), isEmpty);
      });
    }
  });
}
