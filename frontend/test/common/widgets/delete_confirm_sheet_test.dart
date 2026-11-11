import 'dart:async';

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/delete_confirm_sheet.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const title = '이 글을 지울까요?';
  const body = '지우면 되돌릴 수 없어요.';
  const confirm = '지우기';

  late int deleteCalls;
  Completer<void>? hold;

  setUp(() {
    deleteCalls = 0;
    hold = null;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => DeleteConfirmSheet(
                  title: title,
                  body: body,
                  confirmLabel: confirm,
                  onDelete: () async {
                    deleteCalls++;
                    await hold?.future;
                  },
                ),
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

  Finder confirmButton() => find.widgetWithText(AppButton, confirm);
  Finder cancelButton() => find.widgetWithText(AppButton, '취소');

  testWidgets('pen D0TvG — 제목 20/700 ink 렌더 30 · 본문 14 muted 1.55 · 확인 328×52 danger · 취소 328×48 text', (tester) async {
    await open(tester);

    final titleStyle = tester.widget<Text>(find.text(title)).style!;
    expect((titleStyle.fontSize, titleStyle.fontWeight, titleStyle.color), (20, FontWeight.w700, AppColors.ink));
    expect(tester.getSize(find.text(title)).height, 30);
    final bodyStyle = tester.widget<Text>(find.text(body)).style!;
    expect((bodyStyle.fontSize, bodyStyle.color, bodyStyle.height), (14, AppColors.muted, 1.55));
    expect(tester.widget<AppButton>(confirmButton()).variant, AppButtonVariant.danger);
    expect(tester.widget<AppButton>(cancelButton()).variant, AppButtonVariant.text);

    // 손잡이 칸 28 → 8 → 제목 → 16 → 본문 → 16 → 확인 → 8 → 취소 → 32, 시트는 화면 바닥에 붙는다.
    final titleRect = tester.getRect(find.text(title));
    final bodyRect = tester.getRect(find.text(body));
    final confirmRect = tester.getRect(confirmButton());
    final cancelRect = tester.getRect(cancelButton());
    expect(titleRect.left, 16);
    expect(bodyRect.top - titleRect.bottom, 16);
    expect(confirmRect.top - bodyRect.bottom, 16);
    expect(confirmRect.size, const Size(328, 52));
    expect(cancelRect.top - confirmRect.bottom, 8);
    expect(cancelRect.size, const Size(328, 48));
    expect(780 - cancelRect.bottom, 32);
  });

  testWidgets('확인을 누르면 onDelete 를 한 번 부르고, 끝나면 시트가 닫힌다', (tester) async {
    await open(tester);

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(deleteCalls, 1);
    expect(find.text(title), findsNothing);
  });

  testWidgets('지우는 중(pen EIEFb) — 확인 버튼이 꺼진 회색이고 도는 표시가 없으며, 다시 눌러도 한 번뿐', (tester) async {
    hold = Completer<void>();
    await open(tester);

    await tester.tap(confirmButton());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(title), findsOneWidget);
    final button = tester.widget<AppButton>(confirmButton());
    expect(button.onPressed, isNull);
    expect(button.isLoading, isFalse);
    final elevated = tester.widget<ElevatedButton>(
      find.descendant(of: confirmButton(), matching: find.byType(ElevatedButton)),
    );
    expect(elevated.style!.backgroundColor!.resolve({WidgetState.disabled}), AppColors.primaryDisabled);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<AppButton>(cancelButton()).onPressed, isNotNull);

    await tester.tap(confirmButton(), warnIfMissed: false);
    await tester.pump();
    expect(deleteCalls, 1);

    hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
  });

  testWidgets('취소는 아무것도 지우지 않고 닫는다', (tester) async {
    await open(tester);

    await tester.tap(cancelButton());
    await tester.pumpAndSettle();

    expect(deleteCalls, 0);
    expect(find.text(title), findsNothing);
  });

  testWidgets('지우는 중에 취소로 먼저 닫았으면 끝나도 또 닫지 않는다(밑 화면이 닫히면 안 된다)', (tester) async {
    hold = Completer<void>();
    await open(tester);
    await tester.tap(confirmButton());
    await tester.pump();

    // 닫히는 애니메이션 도중(시트가 아직 mounted)에 응답이 와야 현재 길 확인이 실제로 쓰인다.
    await tester.tap(cancelButton());
    await tester.pump();
    hold!.complete();
    await tester.pumpAndSettle();

    expect(find.text('열기'), findsOneWidget);
  });
}
