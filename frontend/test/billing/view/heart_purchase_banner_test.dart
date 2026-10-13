import 'package:campus_mate/billing/model/heart_purchase_notice.dart';
import 'package:campus_mate/billing/view/heart_purchase_banner.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pretendard.dart';

void main() {
  setUpAll(loadPretendard);

  Future<void> pump(WidgetTester tester, HeartPurchaseNotice notice, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Column(children: [HeartPurchaseBanner(notice: notice)])),
      ),
    );
  }

  Color? fill(WidgetTester tester) =>
      tester.widget<Container>(find.descendant(of: find.byType(HeartPurchaseBanner), matching: find.byType(Container)).first).color;

  testWidgets('지급 지연(15e-6 `xJ0HR`) — 360 폭 · 분홍 #FFF0F2 · timer 20 #C4224B · 제목 14/600 ink · 설명 12 muted', (tester) async {
    await pump(tester, HeartPurchaseNotice.delayed);

    final banner = find.byType(HeartPurchaseBanner);
    expect(tester.getSize(banner).width, 360);
    expect(fill(tester), AppColors.primaryWash);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect((icon.icon, icon.size, icon.color), (AppIcons.timer, 20, AppColors.primaryText));
    final title = tester.widget<Text>(find.text('하트 지급이 늦어지고 있어요')).style!;
    expect((title.fontSize, title.fontWeight, title.color, title.height), (14, FontWeight.w600, AppColors.ink, 1.5));
    final caption = tester.widget<Text>(find.text('앱을 다시 열면 이어서 들어와요')).style!;
    expect((caption.fontSize, caption.color, caption.height), (12, AppColors.muted, 1.5));
    // pen: 아이콘 x16, 글자 x46(아이콘 20 + 간격 10), 위 12, 제목 ↔ 설명 2.
    expect(tester.getTopLeft(find.byType(Icon)).dx, 16);
    expect(tester.getTopLeft(find.text('하트 지급이 늦어지고 있어요')), const Offset(46, 12));
    expect(
      tester.getTopLeft(find.text('앱을 다시 열면 이어서 들어와요')).dy - tester.getBottomLeft(find.text('하트 지급이 늦어지고 있어요')).dy,
      2,
    );
  });

  testWidgets('오류 배너(결제 불가 15e-7 `b8MFOu`) — #FAEFEC · triangle-alert · 제목 #C13515', (tester) async {
    await pump(tester, HeartPurchaseNotice.unavailable);

    expect(fill(tester), AppColors.errorWash);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect((icon.icon, icon.color), (AppIcons.alertTriangle, AppColors.error));
    expect(tester.widget<Text>(find.text('지금은 하트를 살 수 없어요')).style!.color, AppColors.error);
    expect(find.text('구글 플레이에 로그인했는지 확인해 주세요'), findsOneWidget);
  });

  testWidgets('아이콘은 pen 대로 — 대기 timer · 다른 계정 info · 실패 · 확인 실패 triangle-alert', (tester) async {
    for (final (notice, glyph) in [
      (HeartPurchaseNotice.pending, AppIcons.timer),
      (HeartPurchaseNotice.otherAccount, AppIcons.info),
      (HeartPurchaseNotice.failed, AppIcons.alertTriangle),
      (HeartPurchaseNotice.invalid, AppIcons.alertTriangle),
    ]) {
      await pump(tester, notice);
      expect(tester.widget<Icon>(find.byType(Icon)).icon, glyph, reason: notice.name);
    }
  });

  testWidgets('닫기 버튼이 없다(대장 결정 10-13)', (tester) async {
    await pump(tester, HeartPurchaseNotice.failed);

    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('확인 실패의 긴 설명(메일 주소)은 잘리지 않고 줄이 늘어난다 — 글자 2.0 에서도 넘침 없음', (tester) async {
    await pump(tester, HeartPurchaseNotice.invalid, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.textContaining('appmailerl4538@gmail.com')).maxLines, isNull);
  });
}
