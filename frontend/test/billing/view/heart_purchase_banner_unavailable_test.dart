import 'package:campus_mate/billing/model/heart_purchase_notice.dart';
import 'package:campus_mate/billing/model/heart_unavailable.dart';
import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:campus_mate/billing/view/heart_purchase_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pretendard.dart';

void main() {
  setUpAll(loadPretendard);

  Future<void> pump(WidgetTester tester, PaymentStore store, HeartUnavailable? unavailable) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [HeartPurchaseBanner(notice: HeartPurchaseNotice.unavailable, store: store, unavailable: unavailable)],
          ),
        ),
      ),
    );
  }

  testWidgets('App Store — 원인마다 설명 글자만 다르고 제목은 그대로다', (tester) async {
    for (final (reason, missing, caption) in [
      (
        HeartUnavailableReason.storeUnusable,
        0,
        '이 기기에서 App Store 결제를 쓸 수 없어요 · 설정 > 스크린 타임 > 콘텐츠 및 개인정보 보호 > iTunes 및 App Store 구입 > 앱 내 구입을 확인해 주세요',
      ),
      (
        HeartUnavailableReason.noProducts,
        5,
        '상품 정보를 불러오지 못했어요 · App Store 상품이 아직 준비 중일 수 있어요 (못 찾은 상품 5개)',
      ),
      (HeartUnavailableReason.serverStatus, 0, '서버에서 상태를 읽지 못했어요 · 잠시 뒤 다시 시도해 주세요'),
    ]) {
      await pump(tester, PaymentStore.appStore, HeartUnavailable(reason, missingProducts: missing));

      expect(find.text('지금은 하트를 살 수 없어요'), findsOneWidget, reason: reason.name);
      expect(find.text(caption), findsOneWidget, reason: reason.name);
    }
  });

  testWidgets('구글 플레이는 원인이 있어도 설명이 그대로다', (tester) async {
    await pump(tester, PaymentStore.googlePlay, const HeartUnavailable(HeartUnavailableReason.noProducts, missingProducts: 5));

    expect(find.text('구글 플레이에 로그인했는지 확인해 주세요'), findsOneWidget);
  });
}
