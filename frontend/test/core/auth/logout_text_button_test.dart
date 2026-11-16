import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/core/auth/logout_text_button.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int signOutCalls;

  Future<void> pump(WidgetTester tester) async {
    signOutCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signOutProvider.overrideWithValue(() async => signOutCalls++)],
        // 관문 화면처럼 세로 Column 아래에 둔다 — 높이가 열려 있어야 최소 48 이 보인다.
        child: const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: Column(children: [LogoutTextButton()]))),
      ),
    );
  }

  testWidgets('pen u05wB — 높이 48 · 14/600 muted', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.byType(InkWell)).height, 48);
    final label = tester.widget<Text>(find.text('로그아웃'));
    expect(label.style!.fontSize, 14);
    expect(label.style!.fontWeight, FontWeight.w600);
    expect(label.style!.color, AppColors.muted);
  });

  testWidgets('누르면 16g 확인 팝업(설명 없음 변형)으로 묻고, 확인하면 로그아웃을 한 번 부른다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.text('로그아웃할까요?'), findsOneWidget);
    // 사용자 2026-11-16 「"로그아웃할까요?"-> 이것만」 — 설명 줄이 없다.
    expect(find.descendant(of: find.byKey(confirmPopupCardKey), matching: find.byType(Text)), findsNWidgets(3));
    expect(find.textContaining('다시 로그인하려면'), findsNothing);

    await tester.tap(find.descendant(of: find.byKey(confirmPopupCardKey), matching: find.text('로그아웃')));
    await tester.pumpAndSettle();

    expect(signOutCalls, 1);
  });

  testWidgets('시트를 그냥 닫으면 로그아웃하지 않는다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(signOutCalls, 0);
  });
}
