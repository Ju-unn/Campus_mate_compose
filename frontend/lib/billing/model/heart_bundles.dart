/// 하트 번들 한 묶음(pen `w0vIYG` HeartBundleCard).
///
/// **목(서버 값 미정)** — 번들 · 가격 · 할인율을 내려 주는 서버가 아직 없어 pen(`IAy1j` 카드 5장)의 값을 상수로 둔다.
/// 서버가 생기면 이 파일만 읽기 모델로 바꾼다(숫자를 화면 곳곳에 두지 않는다).
class HeartBundle {
  const HeartBundle({
    required this.hearts,
    required this.price,
    required this.asset,
    this.originalPrice,
    this.discountPercent,
    this.isMaxDiscount = false,
    this.isRecommended = false,
  });

  final int hearts;

  /// 원(₩).
  final int price;

  /// 할인 전 가격. 할인이 없으면 null.
  final int? originalPrice;
  final int? discountPercent;

  /// "최대 할인" 글(pen `wWEMu`) — 가장 큰 번들만.
  final bool isMaxDiscount;

  /// "추천" 태그(pen `Fs0PO`) — 처음부터 선택돼 있는 번들.
  final bool isRecommended;

  /// 카드 그림 56×56(pen `d7TRT`).
  final String asset;

  /// "100하트".
  String get quantityLabel => '$hearts하트';
}

/// 처음부터 고른 번들 — pen `J0o8uB` 100하트(분홍 테두리).
const int defaultHeartBundleIndex = 1;

/// pen `IAy1j` 카드 5장(`nn49S` · `J0o8uB` · `Q0F9Ta` · `l5zO0` · `KLF2n`). 목 — 위 설명 참고.
const List<HeartBundle> heartBundles = [
  HeartBundle(hearts: 50, price: 3000, asset: 'assets/images/heart-bundle-50-v1.png'),
  HeartBundle(
    hearts: 100,
    price: 5700,
    originalPrice: 6000,
    discountPercent: 5,
    isRecommended: true,
    asset: 'assets/images/heart-bundle-100-v1.png',
  ),
  HeartBundle(
    hearts: 200,
    price: 10800,
    originalPrice: 12000,
    discountPercent: 10,
    asset: 'assets/images/heart-bundle-200-v1.png',
  ),
  HeartBundle(
    hearts: 400,
    price: 20400,
    originalPrice: 24000,
    discountPercent: 15,
    asset: 'assets/images/heart-bundle-400-v1.png',
  ),
  HeartBundle(
    hearts: 800,
    price: 38400,
    originalPrice: 48000,
    discountPercent: 20,
    isMaxDiscount: true,
    asset: 'assets/images/heart-bundle-800-v1.png',
  ),
];

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
