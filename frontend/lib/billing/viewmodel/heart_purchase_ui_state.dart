import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/model/heart_purchase_notice.dart';
import 'package:campus_mate/billing/model/heart_unavailable.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';

/// 구매 진행 단계. [purchasing] 결제 창 대기(18d-3) · [verifying] 서버 확인 중(15e-3) · [delayed] 지급 지연(15e-6).
enum HeartPurchasePhase { idle, purchasing, verifying, delayed }

/// 스토어 결제를 쓸 수 있는지. 읽는 중(loading)은 pen 에 없는 상태다 — 구매 버튼만 꺼 둔다.
enum HeartStoreAvailability { loading, available, unavailable }

/// 잠깐 뜨는 토스트(pen Toast `I8UOWm`). 화면이 2초 보여 주고 [HeartPurchaseViewModel.clearToast] 로 지운다.
sealed class HeartPurchaseToast {
  const HeartPurchaseToast();

  String get message;
}

/// 성공(15e-4 `X0G8Fz` · 15e-5 `ksBC8`). 서버 응답 숫자로만 말한다(계획서 6-4, 사용자 확정 문구 10-13).
final class GrantedToast extends HeartPurchaseToast {
  const GrantedToast({required this.hearts, required this.bonusHearts});

  final int hearts;
  final int bonusHearts;

  @override
  String get message =>
      bonusHearts == 0 ? '$hearts하트가 들어왔어요' : '${hearts + bonusHearts}하트가 들어왔어요(보너스 $bonusHearts 포함)';
}

/// 취소 · 이미 처리(15e-8).
final class NoticeToast extends HeartPurchaseToast {
  const NoticeToast(this.notice);

  final HeartPurchaseNotice notice;

  @override
  String get message => notice.title;
}

/// 처음 고른 번들(pen `J0o8uB` 100하트) — [defaultHeartBundleIndex] 와 같은 상품. 기본 인자라 상수로 둔다.
const String defaultHeartProductId = 'heart_100';

/// 15e 하트 상점 · 18d 구매 확인 시트의 구매 상태 하나.
class HeartPurchaseUiState {
  const HeartPurchaseUiState({
    this.availability = HeartStoreAvailability.loading,
    this.prices = const {},
    this.bonus,
    this.accountToken,
    this.selectedProductId = defaultHeartProductId,
    this.phase = HeartPurchasePhase.idle,
    this.banner,
    this.toast,
    this.unavailable,
  });

  final HeartStoreAvailability availability;

  /// 스토어가 준 가격(상품 ID → 가격). 없는 상품은 앱 상수 가격을 보여 주되 사지 못한다.
  final Map<String, StorePrice> prices;

  /// 첫 구매 자격(서버). null 이면 배지 · 보너스 줄이 없다.
  final FirstPurchaseBonus? bonus;

  /// 구매 창에 싣는 계정 표시. 서버 상태를 못 읽었으면 null 이라 사지 못한다.
  final String? accountToken;

  final String selectedProductId;
  final HeartPurchasePhase phase;

  /// 앱바 아래 배너. 다시 구매하거나 상점을 나가면 사라진다.
  final HeartPurchaseNotice? banner;
  final HeartPurchaseToast? toast;

  /// 결제 불가 배너의 원인(설명 글자 · 로그). 불가가 아니면 null.
  final HeartUnavailable? unavailable;

  bool canBuy(String productId) =>
      availability == HeartStoreAvailability.available &&
      phase == HeartPurchasePhase.idle &&
      accountToken != null &&
      prices.containsKey(productId);

  /// 앱 상수 번들에 스토어 가격을 씌운다.
  HeartBundle priced(HeartBundle bundle) => bundle.withStorePrice(prices[bundle.productId]);

  HeartBundle get selectedBundle => priced(heartBundles.firstWhere((bundle) => bundle.productId == selectedProductId));

  /// 이 번들에 붙는 첫 구매 보너스 하트(없으면 null).
  int? bonusFor(HeartBundle bundle) {
    final current = bonus;
    return current != null && current.appliesTo(bundle.hearts) ? current.hearts : null;
  }

  HeartPurchaseUiState copyWith({
    HeartStoreAvailability? availability,
    Map<String, StorePrice>? prices,
    Object? bonus = _keep,
    Object? accountToken = _keep,
    String? selectedProductId,
    HeartPurchasePhase? phase,
    Object? banner = _keep,
    Object? toast = _keep,
    Object? unavailable = _keep,
  }) {
    return HeartPurchaseUiState(
      availability: availability ?? this.availability,
      prices: prices ?? this.prices,
      bonus: identical(bonus, _keep) ? this.bonus : bonus as FirstPurchaseBonus?,
      accountToken: identical(accountToken, _keep) ? this.accountToken : accountToken as String?,
      selectedProductId: selectedProductId ?? this.selectedProductId,
      phase: phase ?? this.phase,
      banner: identical(banner, _keep) ? this.banner : banner as HeartPurchaseNotice?,
      toast: identical(toast, _keep) ? this.toast : toast as HeartPurchaseToast?,
      unavailable: identical(unavailable, _keep) ? this.unavailable : unavailable as HeartUnavailable?,
    );
  }
}

/// copyWith 에서 "그대로 둠" 과 "null 로 지움" 을 가르는 표식.
const Object _keep = Object();
