import 'package:campus_mate/common/failure.dart';

/// 하트 구매 안내 · 오류(pen 15e-8 `JGoPI`, 계획서 7-2 표). [isBanner] 면 앱바 아래 배너(pen Alert `teNRJ`, 제목 + 설명),
/// 아니면 잠깐 뜨는 토스트(pen Toast `I8UOWm`, 제목만)다. 배너는 다시 구매를 시도하거나 상점을 나가면 사라진다(닫기 버튼 없음).
///
/// 글자(제목 · 설명)는 view 쪽 확장 `heart_store_text.dart` 가 정한다(문구 파일 ARB `billingPurchaseNotice*`).
/// 문구는 서버 `detail` 이 아니라 pen 글자를 쓴다 — 서버 PURCHASE_INVALID 글자는 pen 과 다르다(구현 편차 기록).
enum HeartPurchaseNotice {
  /// 토스트 `imxbJ`(info) — 결제 창에서 취소.
  canceled,

  /// 토스트 `bs9a7`(circle-check) — 서버 409 purchase_token_used.
  alreadyProcessed,

  /// 토스트(info, pen 에 없음 — 후속) — 서버 422 purchase_revoked(애플이 환불한 거래). 하트 없이 거래를 끝낸다.
  revoked,

  /// 배너 `Qufgn`(timer) — 결제 창 pending · 서버 202.
  pending(isBanner: true),

  /// 배너 `v2uyG1`(timer) — 서버 503 · 네트워크 실패. 구매를 끝내지 않아 다음 복구 때 이어서 들어온다.
  delayed(isBanner: true),

  /// 빨간 배너 `mvOHm`(triangle-alert) — 결제 창 error(카드 거절 등).
  failed(isBanner: true, isError: true),

  /// 빨간 배너 `F6cXu` — 서버 422 purchase_invalid.
  invalid(isBanner: true, isError: true),

  /// 배너 `wvbOe`(info) — 서버 409 purchase_other_account.
  otherAccount(isBanner: true),

  /// 빨간 배너 `YOhKL` — 스토어를 쓸 수 없음 · 가격 0개 · 서버 상태를 못 읽음. App Store 설명은 pen 에 없다(후속) —
  /// 아이폰은 원인이 로그인이 아니라 기기의 앱 내 구입 제한 · 상품 미등록 · 심사 전이라 원인을 가리지 않는 글자로 둔다.
  /// 설명은 App Store 에서만 다르게 말한다(스토어 이름이 든 것만, view 쪽 확장).
  unavailable(isBanner: true, isError: true);

  const HeartPurchaseNotice({this.isBanner = false, this.isError = false});

  /// 앱바 아래 배너(설명이 있다). 아니면 토스트.
  final bool isBanner;

  /// 빨간 오류 배너(pen 채움 #FAEFEC · 글자 #C13515).
  final bool isError;

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
