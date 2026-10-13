import 'package:campus_mate/billing/model/store_purchase.dart';

/// 하트 1개의 기준가(원, 2026-09-14 확정 — DESIGN §13-114). 원가 · 할인율은 판매가를 이 값과 견줘 계산한다.
const int heartUnitWon = 60;

/// 하트 번들 한 묶음(pen `w0vIYG` HeartBundleCard). 상품 ID 는 구글 플레이 상품 · 서버 상품표와 같은 글자다.
///
/// 가격은 스토어가 준 값이 먼저다(화면 가격 = 실제 청구 가격, 계획서 6-3). 스토어 가격을 아직 못 읽었으면 아래 상수 가격을
/// 보여 주고, 그때는 구매 버튼이 꺼져 있다.
class HeartBundle {
  const HeartBundle({
    required this.productId,
    required this.hearts,
    required this.price,
    required this.asset,
    this.storePriceLabel,
    this.isMaxDiscount = false,
    this.isRecommended = false,
  });

  final String productId;
  final int hearts;

  /// 원(₩). 스토어가 원화가 아닌 가격을 주면 null 이고 [storePriceLabel] 만 쓴다.
  final int? price;

  /// 원화가 아닌 스토어 가격 글자(예: "US$4.99").
  final String? storePriceLabel;

  /// "최대 할인" 글(pen `wWEMu`) — 가장 큰 번들만.
  final bool isMaxDiscount;

  /// "추천" 태그(pen `Fs0PO`) — 처음부터 선택돼 있는 번들.
  final bool isRecommended;

  /// 카드 그림 56×56(pen `d7TRT`).
  final String asset;

  /// "100하트".
  String get quantityLabel => '$hearts하트';

  /// "5,700원" — 원화가 아니면 스토어 글자 그대로.
  String get priceLabel {
    final won = price;
    return won == null ? storePriceLabel ?? '' : '${formatWon(won)}원';
  }

  /// 할인 전 가격(하트 × 60원). 판매가가 그보다 작을 때만 있다.
  int? get originalPrice {
    final won = price;
    final full = hearts * heartUnitWon;
    return won != null && won < full ? full : null;
  }

  int? get discountPercent {
    final full = originalPrice;
    return full == null ? null : 100 - (price! * 100 / full).round();
  }

  bool get showsDiscount => discountPercent != null;

  /// 스토어가 준 가격으로 바꾼 번들. [store] 가 null 이면(못 읽음) 그대로다.
  HeartBundle withStorePrice(StorePrice? store) {
    if (store == null) return this;
    return HeartBundle(
      productId: productId,
      hearts: hearts,
      price: store.won,
      storePriceLabel: store.label,
      asset: asset,
      isMaxDiscount: isMaxDiscount,
      isRecommended: isRecommended,
    );
  }
}

/// 처음부터 고른 번들 — pen `J0o8uB` 100하트(분홍 테두리).
const int defaultHeartBundleIndex = 1;

/// pen `IAy1j` 카드 5장(`nn49S` · `J0o8uB` · `Q0F9Ta` · `l5zO0` · `KLF2n`). 가격은 스토어 가격을 못 읽었을 때의 폴백이다
/// (서버 DB 함수 grant_store_purchase 의 상품표 · 구글 플레이 콘솔 가격과 같은 값).
const List<HeartBundle> heartBundles = [
  HeartBundle(productId: 'heart_50', hearts: 50, price: 3000, asset: 'assets/images/heart-bundle-50-v1.png'),
  HeartBundle(
    productId: 'heart_100',
    hearts: 100,
    price: 5700,
    isRecommended: true,
    asset: 'assets/images/heart-bundle-100-v1.png',
  ),
  HeartBundle(productId: 'heart_200', hearts: 200, price: 10800, asset: 'assets/images/heart-bundle-200-v1.png'),
  HeartBundle(productId: 'heart_400', hearts: 400, price: 20400, asset: 'assets/images/heart-bundle-400-v1.png'),
  HeartBundle(
    productId: 'heart_800',
    hearts: 800,
    price: 38400,
    isMaxDiscount: true,
    asset: 'assets/images/heart-bundle-800-v1.png',
  ),
];

/// 스토어에 가격을 물을 상품 ID 다섯 개.
final Set<String> heartProductIds = {for (final bundle in heartBundles) bundle.productId};

/// 3000 → "3,000". 천 단위마다 쉼표.
String formatWon(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
