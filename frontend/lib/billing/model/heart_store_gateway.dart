import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 스토어(구글 플레이 · App Store) 결제 창구. in_app_purchase 를 뷰모델이 직접 부르지 않게 이 뒤에 둔다 — 테스트는 Fake.
abstract interface class HeartStoreGateway {
  /// 이 기기에서 스토어 결제를 쓸 수 있는지(플레이 스토어 없음 · 로그인 안 함 · 앱 내 구입 제한이면 false).
  Future<bool> isAvailable();

  /// productId → 가격. 스토어가 모르는 상품은 빠진다.
  Future<Map<String, StorePrice>> loadPrices(Set<String> productIds);

  /// 결제 결과. 앱이 켜져 있는 동안 계속 흐른다.
  Stream<List<StorePurchaseEvent>> get events;

  /// 결제 창을 연다. 결과는 [events] 로 온다. 창을 못 열면 false.
  Future<bool> buy(String productId, String accountToken);

  /// 끝나지 않은 지난 구매를 [events] 로 다시 흘려보낸다(앱이 꺼졌던 사이 · 지급이 늦어진 결제).
  Future<void> recover();

  /// 서버가 하트를 넣었다고 답한 구매를 끝낸다. 구글은 서버가 지급 뒤 소비(= 확인)로 끝내므로 아무것도 하지 않고(계획서 2-2),
  /// 애플은 이때 거래를 끝낸다(finish). 서버가 지급하기 전에 부르면 안 된다 — 끝낸 거래는 다시 오지 않아 늦어진 지급을 되살릴 수 없다.
  Future<void> finish(String purchaseToken);
}

/// 아무것도 하지 않는 창구 — provider 기본값. 진짜 창구는 앱 진입점(main.dart)이 안드로이드 · iOS 에서만 끼운다
/// (platformHeartStoreGateway).
/// 시험 바인딩의 기본 플랫폼이 안드로이드라, 기본값이 진짜면 하트 상점을 그리는 모든 시험이 플러그인 채널을 건드린다.
class NoHeartStoreGateway implements HeartStoreGateway {
  const NoHeartStoreGateway();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<Map<String, StorePrice>> loadPrices(Set<String> productIds) async => const {};

  @override
  Stream<List<StorePurchaseEvent>> get events => const Stream.empty();

  @override
  Future<bool> buy(String productId, String accountToken) async => false;

  @override
  Future<void> recover() async {}

  @override
  Future<void> finish(String purchaseToken) async {}
}

/// 하트 구매 뷰모델이 쓰는 창구. 테스트는 Fake 로, 안드로이드 · iOS 앱은 main.dart 가 진짜로 덮는다.
final heartStoreGatewayProvider = Provider<HeartStoreGateway>((ref) => const NoHeartStoreGateway());
