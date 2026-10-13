import 'dart:async';

import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';

/// 스토어가 준 것처럼 만든 원화 가격 다섯 개(앱 상수와 같은 값).
Map<String, StorePrice> storePricesWon() => {
      for (final bundle in heartBundles)
        bundle.productId: StorePrice(label: '₩${formatWon(bundle.price!)}', won: bundle.price),
    };

/// 뷰모델 · 화면 시험용 가짜 결제 창구. 결제 창 결과는 [emit] 으로 흘린다.
class FakeHeartStoreGateway implements HeartStoreGateway {
  bool available = true;
  Map<String, StorePrice> prices = storePricesWon();

  /// false 면 결제 창을 못 연 것으로 한다.
  bool opens = true;

  /// [recover] 가 불리면 흘릴 소비 안 된 지난 결제(대기 구매 복구 흐름).
  List<StorePurchaseEvent> unconsumed = const [];

  final List<(String, String)> bought = [];
  int recoverCount = 0;
  int availableCount = 0;

  final StreamController<List<StorePurchaseEvent>> _events = StreamController<List<StorePurchaseEvent>>.broadcast();

  void emit(List<StorePurchaseEvent> events) => _events.add(events);

  @override
  Stream<List<StorePurchaseEvent>> get events => _events.stream;

  @override
  Future<bool> isAvailable() async {
    availableCount++;
    return available;
  }

  @override
  Future<Map<String, StorePrice>> loadPrices(Set<String> productIds) async => {
        for (final entry in prices.entries)
          if (productIds.contains(entry.key)) entry.key: entry.value,
      };

  @override
  Future<bool> buy(String productId, String accountToken) async {
    bought.add((productId, accountToken));
    return opens;
  }

  @override
  Future<void> recover() async {
    recoverCount++;
    if (unconsumed.isNotEmpty) emit(unconsumed);
  }
}
