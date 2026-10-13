import 'package:campus_mate/billing/view/heart_payment_notice.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/consent/model/consent_links.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Uri> opened;
  late bool opens;

  setUp(() {
    opened = [];
    opens = true;
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openUrlProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return opens;
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: SizedBox(width: 328, child: HeartPaymentNotice()))),
      ),
    );
  }

  testWidgets('pen `bBjRD` 세 줄 — 12/400 muted 두 줄 + 링크 12/600 primaryText, 줄높이 1.5 · 사이 4', (tester) async {
    await pump(tester);

    for (final line in ['결제는 구글 플레이로 처리돼요', '결제 취소 · 환불은 구글 플레이 환불 절차를 따라요']) {
      final style = tester.widget<Text>(find.text(line)).style!;
      expect((style.fontSize, style.fontWeight, style.color, style.height), (12, FontWeight.w400, AppColors.muted, 1.5));
    }
    final link = tester.widget<Text>(find.text('유료 서비스 약관 ›')).style!;
    expect((link.fontSize, link.fontWeight, link.color, link.height), (12, FontWeight.w600, AppColors.primaryText, 1.5));
    final store = tester.getRect(find.text('결제는 구글 플레이로 처리돼요'));
    final refund = tester.getRect(find.text('결제 취소 · 환불은 구글 플레이 환불 절차를 따라요'));
    final terms = tester.getRect(find.text('유료 서비스 약관 ›'));
    expect((refund.top - store.bottom, terms.top - refund.bottom), (4, 4));
  });

  testWidgets('iOS 는 App Store 판 두 줄(pen 후속) — 구글 플레이를 말하지 않고 모양은 같다', (tester) async {
    await pump(tester);

    expect(find.text('결제는 App Store로 처리돼요'), findsOneWidget);
    expect(find.text('결제 취소 · 환불은 App Store 환불 절차를 따라요'), findsOneWidget);
    expect(find.textContaining('구글'), findsNothing);
    final style = tester.widget<Text>(find.text('결제는 App Store로 처리돼요')).style!;
    expect((style.fontSize, style.color, style.height), (12, AppColors.muted, 1.5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('"환불" 은 있어도 하네스 금지어(환급 · 선물 · 송금 · 현금 · 출금)는 없다(E-HEART-49)', (tester) async {
    await pump(tester);

    for (final word in ['환급', '선물', '송금', '현금', '출금']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('약관 링크는 노션 유료 서비스 약관(공개 주소)을 기기 브라우저로 연다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('유료 서비스 약관 ›'));
    await tester.pump();

    expect(opened, [paidServiceTermsLink]);
    expect(paidServiceTermsLink.toString(), 'https://golden-leech-197.notion.site/3e9d998f0dee8082be84e126630b02a7');
  });

  testWidgets('못 열면 실패 토스트', (tester) async {
    opens = false;
    await pump(tester);

    await tester.tap(find.text('유료 서비스 약관 ›'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AppToast), findsOneWidget);
  });

  testWidgets('링크는 낭독기에 링크로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(tester.getSemantics(find.text('유료 서비스 약관 ›')).flagsCollection.isLink, isTrue);
    handle.dispose();
  });
}
