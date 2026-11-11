import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/empty_notice.dart';
import 'package:campus_mate/common/widgets/full_screen_notice.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageKey = ValueKey('image');
  const noticeKey = ValueKey('notice');

  Future<void> pump(WidgetTester tester, {double textScale = 1, Widget Function(Widget region)? regionBuilder}) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: FullScreenNotice(
            regionBuilder: regionBuilder,
            notice: const EmptyNotice(
              key: noticeKey,
              align: EmptyNoticeAlign.top,
              image: SizedBox(key: imageKey),
              title: '인터넷에 연결되어 있지 않아요',
              description: '연결을 확인한 뒤 다시 시도해 주세요',
            ),
            button: AppButton(label: '다시 시도', onPressed: () {}),
          ),
        ),
      ),
    );
  }

  testWidgets('pen NWGuf · vGd3l — 안내는 위 120 + 간격 20 아래, 버튼은 바닥 풀폭 312×52(아래 여백 40)', (tester) async {
    await pump(tester);

    expect(tester.getTopLeft(find.byKey(noticeKey)).dy, 120 + 20);
    expect(tester.getRect(find.byKey(imageKey)).top, 120 + 20 + 48);
    final button = tester.getRect(find.widgetWithText(AppButton, '다시 시도'));
    expect(button.size, const Size(312, 52));
    expect(button.left, 24);
    expect(780 - button.bottom, 40);
  });

  testWidgets('버튼 위 20 — 안내 칸은 버튼 위 20 까지만 쓴다', (tester) async {
    await pump(tester, textScale: 2);

    final region = tester.getRect(find.byType(SingleChildScrollView));
    expect(tester.getRect(find.widgetWithText(AppButton, '다시 시도')).top - region.bottom, 20);
  });

  testWidgets('글자를 2배로 키우면 안내만 스크롤하고 버튼은 바닥에 남는다', (tester) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(780 - tester.getRect(find.widgetWithText(AppButton, '다시 시도')).bottom, 40);
  });

  testWidgets('regionBuilder 로 안내 칸을 감쌀 수 있다(토스트 층)', (tester) async {
    await pump(tester, regionBuilder: (region) => Stack(key: const ValueKey('layer'), children: [Positioned.fill(child: region)]));

    expect(find.descendant(of: find.byKey(const ValueKey('layer')), matching: find.byKey(noticeKey)), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(noticeKey)).dy, 120 + 20);
  });

  testWidgets('큰 안내 제목 스타일 — navTitle 20/700 ink 줄높이 1.5(렌더 30)', (tester) async {
    expect(EmptyNotice.largeTitleStyle.fontSize, 20);
    expect(EmptyNotice.largeTitleStyle.fontWeight, FontWeight.w700);
    expect(EmptyNotice.largeTitleStyle.color, AppColors.ink);
    expect(EmptyNotice.largeTitleStyle.height, 1.5);
    expect(EmptyNotice.largeTitleStyle.letterSpacing, AppTypography.navTitle.letterSpacing);
  });
}
