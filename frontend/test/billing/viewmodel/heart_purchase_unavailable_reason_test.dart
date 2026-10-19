import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/billing/model/billing_repository_provider.dart';
import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/heart_unavailable.dart';
import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../me/model/fake_me_repository.dart';
import '../model/fake_billing_repository.dart';
import '../model/fake_heart_store_gateway.dart';

/// 결제 불가 배너의 원인 가르기 — 아이폰에서 "지금은 하트를 살 수 없어요" 가 어느 경우인지 화면 · 로그로 안다.
class _ThrowingPricesGateway extends FakeHeartStoreGateway {
  @override
  Future<Map<String, StorePrice>> loadPrices(Set<String> productIds) async => throw Exception('store down');
}

void main() {
  late FakeHeartStoreGateway gateway;
  late FakeBillingRepository repo;
  late ProviderContainer container;
  late List<String?> logs;
  late DebugPrintCallback originalDebugPrint;

  ProviderContainer makeContainer() {
    final made = ProviderContainer(overrides: [
      heartStoreGatewayProvider.overrideWithValue(gateway),
      billingRepositoryProvider.overrideWithValue(repo),
      heartPurchaseSupportedProvider.overrideWithValue(true),
      paymentStoreProvider.overrideWithValue(PaymentStore.appStore),
      meRepositoryProvider.overrideWithValue(FakeMeRepository(const FailureResult(NetworkFailure()))),
    ]);
    addTearDown(made.dispose);
    return made;
  }

  setUp(() {
    gateway = FakeHeartStoreGateway();
    repo = FakeBillingRepository();
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    container = makeContainer();
  });

  Future<HeartPurchaseUiState> openStore() async {
    await container.read(heartPurchaseViewModelProvider.notifier).refresh(fromStore: true);
    await pumpEventQueue();
    return container.read(heartPurchaseViewModelProvider);
  }

  test('스토어를 쓸 수 없으면 storeUnusable', () async {
    gateway.available = false;

    final s = await openStore();

    expect(s.unavailable?.reason, HeartUnavailableReason.storeUnusable);
    expect(logs, contains('하트 상점 결제 불가: storeUnusable (못 찾은 상품 0개)'));
  });

  test('가격이 0개면 noProducts — 못 찾은 상품 5개', () async {
    gateway.prices = {};

    final s = await openStore();

    expect((s.unavailable?.reason, s.unavailable?.missingProducts), (HeartUnavailableReason.noProducts, 5));
    expect(logs, contains('하트 상점 결제 불가: noProducts (못 찾은 상품 5개)'));
  });

  test('가격을 읽다 던지면 noProducts', () async {
    gateway = _ThrowingPricesGateway();
    container = makeContainer();

    final s = await openStore();

    expect((s.unavailable?.reason, s.unavailable?.missingProducts), (HeartUnavailableReason.noProducts, 5));
  });

  test('서버 상태를 못 읽으면 serverStatus', () async {
    repo.status = const FailureResult(NetworkFailure());

    final s = await openStore();

    expect((s.unavailable?.reason, s.unavailable?.missingProducts), (HeartUnavailableReason.serverStatus, 0));
  });

  test('서버가 애플 계정 표시를 안 주면 serverStatus', () async {
    repo.status = Success(BillingStatus(accountToken: fakeAccountToken, bonus: fakeBonus));

    final s = await openStore();

    expect(s.unavailable?.reason, HeartUnavailableReason.serverStatus);
  });

  test('다시 열어 읽으면 원인이 지워진다', () async {
    gateway.prices = {};
    expect((await openStore()).unavailable, isNotNull);
    gateway.prices = storePricesWon();

    final s = await openStore();

    expect((s.availability, s.unavailable, s.banner), (HeartStoreAvailability.available, null, null));
  });
}
