import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/retry_notice.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const message = '불러오지 못했어요';

  /// 360×780 화면에 본문 칸(높이 600)을 두고 [child] 를 놓는다.
  Future<void> pump(WidgetTester tester, Widget child, {double textScale = 1}) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Scaffold(body: Column(children: [SizedBox(height: 600, child: child)])),
      ),
    );
  }

  group('화면용', () {
    testWidgets('문구 16 muted 가운데 → 12 → "다시 시도" 글자 버튼 48 전체 폭, 한가운데', (tester) async {
      await pump(tester, RetryNotice(message: message, onRetry: () {}));

      final text = tester.widget<Text>(find.text(message));
      expect((text.style!.fontSize, text.style!.color, text.textAlign), (16, AppColors.muted, TextAlign.center));
      final button = find.widgetWithText(AppButton, '다시 시도');
      expect(tester.widget<AppButton>(button).variant, AppButtonVariant.text);
      final textRect = tester.getRect(find.text(message));
      final buttonRect = tester.getRect(button);
      expect(buttonRect.top - textRect.bottom, 12);
      expect(buttonRect.height, 48);
      // 사방 24 안쪽에서 전체 폭.
      expect((buttonRect.left, buttonRect.right), (24, 336));
      expect(textRect.center.dx, 180);
      // 본문 칸(0~600)의 세로 가운데.
      expect((textRect.top + buttonRect.bottom) / 2, closeTo(300, 0.5));
    });

    testWidgets('누르면 onRetry', (tester) async {
      var retried = 0;
      await pump(tester, RetryNotice(message: message, onRetry: () => retried++));

      await tester.tap(find.text('다시 시도'));

      expect(retried, 1);
    });

    testWidgets('글자를 2배로 키워 칸을 넘치면 넘침 오류 없이 스크롤한다', (tester) async {
      await pump(tester, RetryNotice(message: '불러오지 못했어요 ' * 30, onRetry: () {}), textScale: 2);

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('끼워 넣기용(구역 · 시트 안)', () {
    testWidgets('감싸기 없이 문구 → 12 → 버튼 조각만, 위에서부터 이어 붙는다', (tester) async {
      await pump(tester, Column(children: [RetryNotice.inline(message: message, onRetry: () {})]));

      expect(find.byType(SingleChildScrollView), findsNothing);
      final textRect = tester.getRect(find.text(message));
      final buttonRect = tester.getRect(find.widgetWithText(AppButton, '다시 시도'));
      expect(textRect.top, closeTo(0, 0.01));
      expect(buttonRect.top - textRect.bottom, 12);
      expect(buttonRect.width, 360);
      expect(tester.widget<Text>(find.text(message)).style!.color, AppColors.muted);
    });
  });
}
