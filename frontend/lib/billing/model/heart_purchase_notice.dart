import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/support_email.dart';

/// 하트 구매 안내 · 오류(pen 15e-8 `JGoPI`, 계획서 7-2 표). [caption] 이 있으면 앱바 아래 배너(pen Alert `teNRJ`),
/// 없으면 잠깐 뜨는 토스트(pen Toast `I8UOWm`)다. 배너는 다시 구매를 시도하거나 상점을 나가면 사라진다(닫기 버튼 없음).
///
/// 문구는 서버 `detail` 이 아니라 pen 글자를 쓴다 — 서버 PURCHASE_INVALID 글자는 pen 과 다르다(구현 편차 기록).
enum HeartPurchaseNotice {
  /// 토스트 `imxbJ`(info) — 결제 창에서 취소.
  canceled('결제를 취소했어요'),

  /// 토스트 `bs9a7`(circle-check) — 서버 409 purchase_token_used.
  alreadyProcessed('이미 처리된 결제예요'),

  /// 토스트(info, pen 에 없음 — 후속) — 서버 422 purchase_revoked(애플이 환불한 거래). 하트 없이 거래를 끝낸다.
  revoked('환불된 결제예요'),

  /// 배너 `Qufgn`(timer) — 결제 창 pending · 서버 202.
  pending('결제 확인을 기다리고 있어요', caption: '확인되면 하트가 들어와요'),

  /// 배너 `v2uyG1`(timer) — 서버 503 · 네트워크 실패. 구매를 끝내지 않아 다음 복구 때 이어서 들어온다.
  delayed('하트 지급이 늦어지고 있어요', caption: '앱을 다시 열면 이어서 들어와요'),

  /// 빨간 배너 `mvOHm`(triangle-alert) — 결제 창 error(카드 거절 등).
  failed('결제가 되지 않았어요', caption: '결제 수단을 확인하고 다시 시도해 주세요', isError: true),

  /// 빨간 배너 `F6cXu` — 서버 422 purchase_invalid.
  invalid('결제를 확인하지 못했어요', caption: '문제가 계속되면 $supportEmail 으로 알려 주세요', isError: true),

  /// 배너 `wvbOe`(info) — 서버 409 purchase_other_account.
  otherAccount('다른 계정으로 결제한 하트예요', caption: '결제한 계정으로 로그인하면 들어와요'),

  /// 빨간 배너 `YOhKL` — 스토어를 쓸 수 없음 · 가격 0개 · 서버 상태를 못 읽음. App Store 설명은 pen 에 없다(후속) —
  /// 아이폰은 원인이 로그인이 아니라 기기의 앱 내 구입 제한 · 상품 미등록 · 심사 전이라 원인을 가리지 않는 글자로 둔다.
  unavailable(
    '지금은 하트를 살 수 없어요',
    caption: '구글 플레이에 로그인했는지 확인해 주세요',
    appStoreCaption: '이 기기에서 App Store 결제를 쓸 수 없거나 상품을 불러오지 못했어요',
    isError: true,
  );

  const HeartPurchaseNotice(this.title, {this.caption, this.appStoreCaption, this.isError = false});

  final String title;
  final String? caption;

  /// App Store 에서 다르게 말하는 설명(스토어 이름이 든 것만). 없으면 [caption] 을 그대로 쓴다.
  final String? appStoreCaption;

  /// 빨간 오류 배너(pen 채움 #FAEFEC · 글자 #C13515).
  final bool isError;

  bool get isBanner => caption != null;

  /// 이 기기 스토어에 맞춘 설명 — 배너가 그린다.
  String? captionOn(PaymentStore store) => store == PaymentStore.appStore ? appStoreCaption ?? caption : caption;

  /// 같은 구매 토큰을 다시 보내도 서버 답이 바뀌지 않는다 — 이 앱이 켜져 있는 동안은 다시 보내지 않는다.
  bool get isFinalForToken => this == alreadyProcessed || this == revoked || this == invalid || this == otherAccount;

  /// 거절이어도 구매를 끝낸다(finish) — 다시 보내도 이 계정에 하트가 들어갈 길이 없는 거래다. 끝내지 않으면 StoreKit 에 남아
  /// 같은 Apple ID 가 같은 상품을 다시 못 산다(storekit_duplicate_product_object). 확인 실패 · 다른 계정은 다음에 들어올 길이
  /// 남아 끝내지 않는다.
  bool get finishesPurchase => this == alreadyProcessed || this == revoked;

  /// POST /billing/google/verify · /billing/apple/verify 실패(두 서버가 같은 code 를 쓴다). 서버 code 로 가르고, 그 밖
  /// (503 billing_unavailable · apple_not_configured · 네트워크 · 500 · 관문)은 모두 지급 지연이다 —
  /// 구매를 끝내지 않았으니 다음 복구(앱 시작 · 상점 진입 · 복귀)에서 다시 보낸다.
  static HeartPurchaseNotice fromVerifyFailure(Failure failure) {
    if (failure is! ServerRejectedFailure) return delayed;
    if (failure.hasCode('purchase_other_account')) return otherAccount;
    if (failure.hasCode('purchase_token_used')) return alreadyProcessed;
    if (failure.hasCode('purchase_revoked')) return revoked;
    if (failure.hasCode('purchase_invalid')) return invalid;
    return delayed;
  }
}
