import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_safety_repository.dart';

/// 16f 차단 목록(pen `Oby6v` — 카드 `JULLG`, 줄 `gNyir`, 해제 시트 `FzXZ4`, 빈 상태 `KLSeQ`).
void main() {
  late FakeSafetyRepository repository;

  setUp(() {
    repository = FakeSafetyRepository()
      ..blocks = Success([
        blockedUserFixture(profileId: 'p2', nickname: '토끼'),
        blockedUserFixture(profileId: 'p3', nickname: '봄바람'),
      ]);
  });

  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [safetyRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BlockListScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Finder unblockButton(String nickname) => find.descendant(
        of: find.ancestor(of: find.text(nickname), matching: find.byKey(blockedRowKey)),
        matching: find.byType(TextButton),
      );

  Finder unblockInk(String nickname) =>
      find.descendant(of: unblockButton(nickname), matching: find.byType(InkWell));

  group('목록', () {
    testWidgets('안내 · 카드 · 연락처 안내 순서, 사이 20(pen c5ovaJ 여백 [12,16,24,16])', (tester) async {
      await pump(tester);

      expect(find.text('차단 목록'), findsOneWidget);
      final caption = tester.getRect(find.text('차단하면 그 대화는 내 목록에서 사라져요.'));
      final body = tester.getRect(find.byType(Scaffold)).top + 56;
      expect(caption.top - body, 12);
      expect(caption.left, 16);
      final card = tester.getRect(find.byKey(blockedCardKey));
      expect(card.top - caption.bottom, 20);
      expect(card.width, 328);
      final notice = find.text('연락처로 차단한 지인은 여기가 아니라 설정 > 연락처 차단에서 관리해요.');
      final noticeBox = tester.getRect(find.ancestor(of: notice, matching: find.byType(Container)).first);
      expect(noticeBox.top - card.bottom, 20);
      expect(tester.getRect(notice).topLeft - noticeBox.topLeft, const Offset(14, 14));
    });

    testWidgets('줄은 68 — 아바타 40 · 닉네임 · "YYYY.MM.DD 차단" · 해제(pen gNyir)', (tester) async {
      await pump(tester);

      final row = tester.getRect(find.byKey(blockedRowKey).first);
      expect(row.height, 68);
      expect(find.text('2026.09.27 차단'), findsNWidgets(2));
      final avatar = tester.getRect(find.byKey(blockedAvatarKey).first);
      expect(avatar.size, const Size(40, 40));
      expect(avatar.left - row.left, 14);
      final name = tester.getRect(find.text('토끼'));
      expect(name.left - avatar.right, 12);
      expect(name.height, 23);
      final date = tester.getRect(find.text('2026.09.27 차단').first);
      expect(date.top - name.bottom, 2);
      expect(date.height, 17);
      expect(tester.widget<Text>(find.text('토끼')).style!.fontWeight, FontWeight.w700);
      expect(tester.widget<Text>(find.text('2026.09.27 차단').first).style!.color, AppColors.muted);
    });

    testWidgets('해제는 보이는 크기 50×32(글자 + 여백 12 씩), 누르는 영역 48 이상, 오른쪽 여백 14', (tester) async {
      await pump(tester);

      final row = tester.getRect(find.byKey(blockedRowKey).first);
      final visible = tester.getRect(unblockInk('토끼'));
      // pen 폭 50 = Pretendard "해제" 26 + 12 × 2. 테스트 글꼴은 한글이 넓어 글자 폭으로 잰다.
      final labelSize = tester.getSize(find.descendant(of: unblockButton('토끼'), matching: find.text('해제')));
      expect(visible.width, labelSize.width + 24);
      expect(visible.width, greaterThanOrEqualTo(50));
      expect(visible.height, 32);
      expect(row.right - visible.right, 14);
      expect(visible.center.dy, closeTo(row.center.dy, 0.5));
      expect(tester.getSize(unblockButton('토끼')).height, greaterThanOrEqualTo(48));
      final label = tester.widget<Text>(find.descendant(of: unblockButton('토끼'), matching: find.text('해제')));
      expect(label.style?.color ?? DefaultTextStyle.of(tester.element(find.text('해제').first)).style.color,
          AppColors.primaryText);
    });

    testWidgets('눌림 효과는 해제 칸 자신의 Material 에 그린다(COMMON §4-2)', (tester) async {
      await pump(tester);

      final material = find.ancestor(of: unblockInk('토끼'), matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(unblockInk('토끼')));
      expect(tester.getSize(material).height, 32);
      // 카드 바탕도 Container 가 아니라 카드 자신의 Material 이 칠한다.
      final card = find.byKey(blockedCardKey);
      expect(tester.widget(card), isA<Material>());
    });
  });

  group('해제', () {
    testWidgets('해제 → 확인 시트(pen FzXZ4) → 해제하면 그 줄이 빠진다', (tester) async {
      await pump(tester);

      await tester.tap(unblockButton('토끼'));
      await tester.pumpAndSettle();
      expect(find.text('차단을 해제할까요?'), findsOneWidget);
      expect(find.text('이 상대가 다시 카드에 나타날 수 있어요. 사라진 대화는 돌아오지 않아요.'), findsOneWidget);
      await tester.tap(find.widgetWithText(SafetySheetButton, '해제'));
      await tester.pumpAndSettle();

      expect(repository.unblocked, ['p2']);
      expect(find.text('토끼'), findsNothing);
      expect(find.text('봄바람'), findsOneWidget);
    });

    testWidgets('취소하면 아무것도 보내지 않는다', (tester) async {
      await pump(tester);

      await tester.tap(unblockButton('토끼'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(repository.unblocked, isEmpty);
      expect(find.text('토끼'), findsOneWidget);
    });

    testWidgets('보내는 동안 해제 버튼을 모두 멈춘다', (tester) async {
      repository.holdUnblock = Completer<void>();
      await pump(tester);

      await tester.tap(unblockButton('토끼'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SafetySheetButton, '해제'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextButton>(unblockButton('봄바람')).onPressed, isNull);
      repository.holdUnblock!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(unblockButton('봄바람')).onPressed, isNotNull);
    });

    testWidgets('실패하면 줄은 남기고 카드 아래에 빨간 한 줄을 띄운다(pen 에 없는 상태)', (tester) async {
      repository.unblockResult = const FailureResult(NetworkFailure());
      await pump(tester);

      await tester.tap(unblockButton('토끼'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SafetySheetButton, '해제'));
      await tester.pumpAndSettle();

      expect(find.text('토끼'), findsOneWidget);
      final error = find.text('네트워크 연결을 확인해 주세요');
      expect(tester.widget<Text>(error).style!.color, AppColors.error);
      expect(tester.getRect(error).top, greaterThan(tester.getRect(find.byKey(blockedCardKey)).bottom));
    });
  });

  group('빈 상태 · 읽는 중 · 실패', () {
    testWidgets('차단한 상대가 없으면 마스코트 120 과 두 줄 — 안내 두 개는 없다(pen KLSeQ)', (tester) async {
      repository.blocks = const Success([]);
      await pump(tester);

      final mascot = find.byWidgetPredicate(
          (widget) => widget is Image && (widget.image as AssetImage).assetName == 'assets/images/mascot-female.png');
      expect(tester.getSize(mascot), const Size(120, 120));
      final title = tester.getRect(find.text('아직 차단한 상대가 없어요'));
      expect(title.top - tester.getRect(mascot).bottom, 24);
      expect(title.height, 25);
      final description = tester.getRect(find.text('신고하거나 차단한 상대가 있으면\n여기에 모여요.'));
      expect(description.top - title.bottom, 8);
      expect(find.text('차단하면 그 대화는 내 목록에서 사라져요.'), findsNothing);
      expect(find.textContaining('연락처로 차단한 지인은'), findsNothing);
    });

    testWidgets('읽는 동안은 도는 표시만 있다', (tester) async {
      repository.holdFetch = Completer<void>();
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [safetyRepositoryProvider.overrideWithValue(repository)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BlockListScreen()),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repository.holdFetch!.complete();
      await tester.pumpAndSettle();
      expect(find.text('토끼'), findsOneWidget);
    });

    testWidgets('읽기에 실패하면 문구와 "다시 시도" — 누르면 다시 읽는다', (tester) async {
      repository.blocks = const FailureResult(NetworkFailure());
      await pump(tester);

      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      repository.blocks = Success([blockedUserFixture(nickname: '토끼')]);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repository.fetchCount, 2);
      expect(find.text('토끼'), findsOneWidget);
    });
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다. 빈 상태도 같이 본다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    for (final empty in [false, true]) {
      testWidgets('글자 배율 $scale${empty ? ' 빈 상태' : ''} 에서 넘치거나 잘리는 글자가 없다', (tester) async {
        if (empty) repository.blocks = const Success([]);
        await pump(tester, scale: scale);

        expect(tester.takeException(), isNull);
        final clipped = [
          for (final element in find.byType(RichText).evaluate())
            if (element.renderObject case final RenderParagraph p
                when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                    p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
              p.text.toPlainText(),
        ];
        expect(clipped, isEmpty);
      });
    }
  }
}
