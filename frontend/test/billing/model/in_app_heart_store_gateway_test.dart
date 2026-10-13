import 'dart:async';

import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/in_app_heart_store_gateway.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    await gateway.finish('tok-1');

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

  group('앱 진입점이 끼우는 창구(platformHeartStoreGateway)', () {
    HeartStoreGateway? on(TargetPlatform platform) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      return platformHeartStoreGateway(() => iap);
    }

    test('안드로이드 → 구글 플레이 창구', () {
      expect(on(TargetPlatform.android), isA<InAppHeartStoreGateway>());
    });

    test('iOS → App Store 창구', () {
      expect(on(TargetPlatform.iOS), isA<AppStoreHeartStoreGateway>());
    });

    test('그 밖(데스크톱)은 null — provider 기본값(아무것도 하지 않는 창구)을 그대로 두고 플러그인도 만들지 않는다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(platformHeartStoreGateway(() => throw StateError('플러그인을 만들면 안 된다')), isNull);
    });
  });

  group('App Store(StoreKit 2)', () {
    const appleToken = '3f2b8c1e-6a4d-4b7e-9c0a-1d2e3f4a5b6c';
    late AppStoreHeartStoreGateway apple;

    /// in_app_purchase_storekit 0.4.13+2 의 SK2 모양 — 거래 번호는 purchaseID(Transaction.id 10진수),
    /// serverVerificationData 는 서명된 거래(JWS). 대기 · 취소는 거래가 없어 purchaseID 가 null 이다.
    PurchaseDetails sk2(PurchaseStatus status, {String id = 'heart_100', String? transactionId = '2000000123456789'}) =>
        PurchaseDetails(
          purchaseID: transactionId,
          productID: id,
          verificationData: PurchaseVerificationData(
            localVerificationData: '{"id":1}',
            serverVerificationData: 'eyJhbGciOiJFUzI1NiJ9.jws.sig',
            source: 'app_store',
          ),
          transactionDate: '1',
          status: status,
        );

    setUp(() {
      when(() => iap.completePurchase(any())).thenAnswer((_) async {});
      when(() => iap.buyConsumable(purchaseParam: any(named: 'purchaseParam'))).thenAnswer((_) async => true);
      apple = AppStoreHeartStoreGateway(iap);
    });

    Future<List<List<StorePurchaseEvent>>> listen() async {
      final received = <List<StorePurchaseEvent>>[];
      final subscription = apple.events.listen(received.add);
      addTearDown(subscription.cancel);
      return received;
    }

    test('구매는 appAccountToken(UUID)을 applicationUserName 으로 — autoConsume 은 넘기지 않는다(iOS 플러그인은 true 만 받는다)', () async {
      await apple.loadPrices({'heart_100'});

      expect(await apple.buy('heart_100', appleToken), isTrue);

      final param = verify(() => iap.buyConsumable(purchaseParam: captureAny(named: 'purchaseParam'))).captured.single
          as PurchaseParam;
      expect((param.productDetails.id, param.applicationUserName), ('heart_100', appleToken));
      verifyNever(
        () => iap.buyConsumable(purchaseParam: any(named: 'purchaseParam'), autoConsume: any(named: 'autoConsume')),
      );
    });

    test('UUID 가 아닌 계정 표시(구글용 64자)로는 결제 창을 열지 않는다 — 플러그인이 말없이 빼고 결제해 계정을 못 가린다', () async {
      await apple.loadPrices({'heart_100'});

      expect(await apple.buy('heart_100', 'a' * 64), isFalse);
      verifyNever(() => iap.buyConsumable(purchaseParam: any(named: 'purchaseParam')));
    });

    test('같은 상품의 끝내지 않은 거래가 있어 플러그인이 던지면 false(뷰모델이 실패 안내 뒤 복구)', () async {
      when(() => iap.buyConsumable(purchaseParam: any(named: 'purchaseParam')))
          .thenThrow(PlatformException(code: 'storekit_duplicate_product_object'));
      await apple.loadPrices({'heart_100'});

      expect(await apple.buy('heart_100', appleToken), isFalse);
    });

    test('스트림 — 결제됨은 JWS 가 아니라 거래 번호(purchaseID)와 함께, 대기 · 취소 · 오류 · 거래 번호 없음은 그대로/실패로', () async {
      final received = await listen();

      stream.add([
        sk2(PurchaseStatus.purchased),
        sk2(PurchaseStatus.pending, transactionId: null),
        sk2(PurchaseStatus.canceled, transactionId: null),
        sk2(PurchaseStatus.error, transactionId: null),
        sk2(PurchaseStatus.purchased, transactionId: null),
      ]);
      await pumpEventQueue();

      final events = received.single;
      expect([for (final e in events) e.runtimeType], [
        StorePurchased,
        StorePurchasePending,
        StorePurchaseCanceled,
        StorePurchaseFailed,
        StorePurchaseFailed,
      ]);
      expect(((events[0] as StorePurchased).productId, (events[0] as StorePurchased).purchaseToken), (
        'heart_100',
        '2000000123456789',
      ));
    });

    test('결제됨만으로는 거래를 끝내지 않는다 — finish(거래 번호)를 받아야 그 플러그인 객체로 completePurchase', () async {
      await listen();
      final paid = sk2(PurchaseStatus.purchased);
      stream.add([paid]);
      await pumpEventQueue();
      verifyNever(() => iap.completePurchase(any()));

      await apple.finish('2000000123456789');

      expect(verify(() => iap.completePurchase(captureAny())).captured.single, same(paid));
      await apple.finish('2000000123456789');
      await apple.finish('999');
      verifyNever(() => iap.completePurchase(any()));
    });

    test('복구는 restorePurchases 가 아니라(소모품은 currentEntitlements 에 없다) 받아 둔 끝내지 않은 거래를 다시 흘린다', () async {
      // 뷰모델이 듣기 전(앱 시작 직후 · 관문 전)에 StoreKit 이 준 거래도 잃지 않는다.
      stream.add([sk2(PurchaseStatus.purchased), sk2(PurchaseStatus.purchased, id: 'heart_200', transactionId: '7')]);
      await pumpEventQueue();
      final received = await listen();

      await apple.recover();
      await pumpEventQueue();

      expect([for (final e in received.single) (e as StorePurchased).purchaseToken], ['2000000123456789', '7']);
      verifyNever(() => iap.restorePurchases(applicationUserName: any(named: 'applicationUserName')));
    });

    test('끝낸 거래는 다시 흘리지 않고, 끝낼 것이 없으면 복구는 아무것도 흘리지 않는다', () async {
      stream.add([sk2(PurchaseStatus.purchased)]);
      await pumpEventQueue();
      await apple.finish('2000000123456789');
      final received = await listen();

      await apple.recover();
      await pumpEventQueue();

      expect(received, isEmpty);
    });

    test('completePurchase 가 던져도 finish 는 던지지 않는다(다음 앱 시작 때 StoreKit 이 다시 준다)', () async {
      when(() => iap.completePurchase(any())).thenThrow(PlatformException(code: 'finish_error'));
      stream.add([sk2(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      await expectLater(apple.finish('2000000123456789'), completes);
    });
  });
}
