import 'dart:async';

import 'package:campus_mate/billing/model/in_app_heart_store_gateway.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mocktail/mocktail.dart';

class _MockInAppPurchase extends Mock implements InAppPurchase {}

class _FakePurchaseParam extends Fake implements PurchaseParam {}

class _FakePurchaseDetails extends Fake implements PurchaseDetails {}

ProductDetails _details(String id, {String price = '₩5,700', double raw = 5700, String currency = 'KRW'}) =>
    ProductDetails(
      id: id,
      title: '하트 100개',
      description: '',
      price: price,
      rawPrice: raw,
      currencyCode: currency,
    );

PurchaseDetails _purchase(PurchaseStatus status, {String id = 'heart_100', String token = 'tok-1'}) => PurchaseDetails(
      purchaseID: 'GPA.1',
      productID: id,
      verificationData: PurchaseVerificationData(localVerificationData: '{}', serverVerificationData: token, source: 'google_play'),
      transactionDate: '1',
      status: status,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_FakePurchaseParam());
    registerFallbackValue(_FakePurchaseDetails());
  });

  late _MockInAppPurchase iap;
  late StreamController<List<PurchaseDetails>> stream;
  late InAppHeartStoreGateway gateway;

  setUp(() {
    iap = _MockInAppPurchase();
    stream = StreamController<List<PurchaseDetails>>.broadcast();
    addTearDown(stream.close);
    when(() => iap.purchaseStream).thenAnswer((_) => stream.stream);
    when(() => iap.isAvailable()).thenAnswer((_) async => true);
    when(() => iap.restorePurchases(applicationUserName: any(named: 'applicationUserName'))).thenAnswer((_) async {});
    when(
      () => iap.buyConsumable(purchaseParam: any(named: 'purchaseParam'), autoConsume: any(named: 'autoConsume')),
    ).thenAnswer((_) async => true);
    when(() => iap.queryProductDetails(any())).thenAnswer(
      (_) async => ProductDetailsResponse(
        productDetails: [_details('heart_100'), _details('heart_200', price: r'US$8.99', raw: 8.99, currency: 'USD')],
        notFoundIDs: const ['heart_50'],
      ),
    );
    gateway = InAppHeartStoreGateway(iap);
  });

  test('가격 — 원화는 정수 원, 다른 통화는 스토어 글자만, 스토어가 모르는 상품은 빠진다', () async {
    final prices = await gateway.loadPrices({'heart_50', 'heart_100', 'heart_200'});

    expect(prices.keys, unorderedEquals(['heart_100', 'heart_200']));
    expect((prices['heart_100']!.label, prices['heart_100']!.won), ('₩5,700', 5700));
    expect((prices['heart_200']!.label, prices['heart_200']!.won), (r'US$8.99', null));
  });

  test('구매는 autoConsume:false + 계정 표시를 applicationUserName 으로 — 서버가 확인 · 지급한 뒤 서버가 소비한다', () async {
    await gateway.loadPrices({'heart_100'});

    final opened = await gateway.buy('heart_100', 'a' * 64);

    expect(opened, isTrue);
    final captured = verify(
      () => iap.buyConsumable(purchaseParam: captureAny(named: 'purchaseParam'), autoConsume: false),
    ).captured;
    final param = captured.single as PurchaseParam;
    expect((param.productDetails.id, param.applicationUserName), ('heart_100', 'a' * 64));
    verifyNever(() => iap.buyConsumable(purchaseParam: any(named: 'purchaseParam')));
  });

  test('가격을 못 읽은 상품은 결제 창을 열지 않는다(false)', () async {
    expect(await gateway.buy('heart_800', 'a' * 64), isFalse);
    verifyNever(
      () => iap.buyConsumable(purchaseParam: any(named: 'purchaseParam'), autoConsume: any(named: 'autoConsume')),
    );
  });

  test('결제 창이 던지면(이미 가진 상품 등) false — 화면은 실패 안내 뒤 복구한다', () async {
    when(
      () => iap.buyConsumable(purchaseParam: any(named: 'purchaseParam'), autoConsume: any(named: 'autoConsume')),
    ).thenThrow(Exception('itemAlreadyOwned'));
    await gateway.loadPrices({'heart_100'});

    expect(await gateway.buy('heart_100', 'a' * 64), isFalse);
  });

  test('스트림 — 결제됨 · 복구 → 토큰과 함께, 대기 · 취소 · 오류는 그대로, 토큰이 비면 실패로', () async {
    final received = <List<StorePurchaseEvent>>[];
    final subscription = gateway.events.listen(received.add);
    addTearDown(subscription.cancel);

    stream.add([
      _purchase(PurchaseStatus.purchased),
      _purchase(PurchaseStatus.restored, token: 'tok-2'),
      _purchase(PurchaseStatus.pending),
      _purchase(PurchaseStatus.canceled, id: ''),
      _purchase(PurchaseStatus.error, id: ''),
      _purchase(PurchaseStatus.purchased, id: '', token: ''),
    ]);
    await pumpEventQueue();

    final events = received.single;
    expect([for (final e in events) e.runtimeType], [
      StorePurchased,
      StorePurchased,
      StorePurchasePending,
      StorePurchaseCanceled,
      StorePurchaseFailed,
      StorePurchaseFailed,
    ]);
    expect([(events[0] as StorePurchased).purchaseToken, (events[1] as StorePurchased).purchaseToken], ['tok-1', 'tok-2']);
  });

  test('안드로이드에서는 앱이 구매를 끝내지 않는다 — completePurchase 를 부르지 않는다(서버가 소비 = 확인 처리)', () async {
    final subscription = gateway.events.listen((_) {});
    addTearDown(subscription.cancel);
    await gateway.loadPrices({'heart_100'});
    await gateway.buy('heart_100', 'a' * 64);

    stream.add([_purchase(PurchaseStatus.purchased), _purchase(PurchaseStatus.restored)]);
    await pumpEventQueue();
    await gateway.recover();

    verifyNever(() => iap.completePurchase(any()));
  });

  test('복구는 restorePurchases(소비 안 된 지난 결제를 스트림으로 다시 흘린다), 실패해도 던지지 않는다', () async {
    await gateway.recover();
    verify(() => iap.restorePurchases()).called(1);

    when(() => iap.restorePurchases(applicationUserName: any(named: 'applicationUserName'))).thenThrow(
      InAppPurchaseException(source: 'google_play', code: 'restore_error', message: '6'),
    );
    await expectLater(gateway.recover(), completes);
  });

  test('isAvailable 이 던지면 false', () async {
    when(() => iap.isAvailable()).thenThrow(Exception('no play store'));

    expect(await gateway.isAvailable(), isFalse);
  });
}
