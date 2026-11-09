import 'package:campus_mate/billing/store/model/data/heart_bundles.dart';
import 'package:campus_mate/billing/store/model/data/heart_purchase_notice.dart';
import 'package:campus_mate/billing/store/model/data/heart_unavailable.dart';
import 'package:campus_mate/billing/store/model/data/payment_store.dart';
import 'package:campus_mate/billing/store/viewmodel/heart_purchase_ui_state.dart';
import 'package:campus_mate/common/support_email.dart';
import 'package:campus_mate/l10n/app_localizations.dart';

/// 하트 상점(15e) · 구매 확인 시트(18d)의 화면 글자(문구 파일 ARB `billing*`). 모델 · 뷰모델은 종류와 숫자만 들고, 글자는 여기서 고른다.
/// 결제 안내는 오류가 아니라 알림이라 `error*` 가 아닌 일반 키다(B8 기본안) — 빨간 배너인지는 [HeartPurchaseNotice.isError] 가 정한다.
extension HeartPurchaseNoticeText on HeartPurchaseNotice {
  String title(AppLocalizations l10n) => switch (this) {
        HeartPurchaseNotice.canceled => l10n.billingPurchaseNoticeCanceled,
        HeartPurchaseNotice.alreadyProcessed => l10n.billingPurchaseNoticeAlreadyProcessed,
        HeartPurchaseNotice.revoked => l10n.billingPurchaseNoticeRevoked,
        HeartPurchaseNotice.pending => l10n.billingPurchaseNoticePending,
        HeartPurchaseNotice.delayed => l10n.billingPurchaseNoticeDelayed,
        HeartPurchaseNotice.failed => l10n.billingPurchaseNoticeFailed,
        HeartPurchaseNotice.invalid => l10n.billingPurchaseNoticeInvalid,
        HeartPurchaseNotice.otherAccount => l10n.billingPurchaseNoticeOtherAccount,
        HeartPurchaseNotice.unavailable => l10n.billingPurchaseNoticeUnavailable,
      };

  /// 배너 설명(구글 플레이 기준). 토스트(취소 · 이미 처리 · 환불)는 설명이 없다.
  String? caption(AppLocalizations l10n) => switch (this) {
        HeartPurchaseNotice.canceled || HeartPurchaseNotice.alreadyProcessed || HeartPurchaseNotice.revoked => null,
        HeartPurchaseNotice.pending => l10n.billingPurchaseNoticePendingCaption,
        HeartPurchaseNotice.delayed => l10n.billingPurchaseNoticeDelayedCaption,
        HeartPurchaseNotice.failed => l10n.billingPurchaseNoticeFailedCaption,
        HeartPurchaseNotice.invalid => l10n.billingPurchaseNoticeInvalidCaption(email: supportEmail),
        HeartPurchaseNotice.otherAccount => l10n.billingPurchaseNoticeOtherAccountCaption,
        HeartPurchaseNotice.unavailable => l10n.billingPurchaseNoticeUnavailableCaption,
      };

  /// 이 기기 스토어에 맞춘 설명 — 스토어 이름이 든 결제 불가만 App Store 에서 다르게 말한다.
  String? captionOn(AppLocalizations l10n, PaymentStore store) =>
      this == HeartPurchaseNotice.unavailable && store == PaymentStore.appStore
          ? l10n.billingPurchaseNoticeUnavailableAppStoreCaption
          : caption(l10n);
}

/// App Store 결제 불가 배너의 원인별 설명. 구글 플레이 설명은 바꾸지 않는다(HeartPurchaseNotice.unavailable).
extension HeartUnavailableText on HeartUnavailable {
  String appStoreCaption(AppLocalizations l10n) => switch (reason) {
        HeartUnavailableReason.storeUnusable => l10n.billingUnavailableStoreUnusable,
        HeartUnavailableReason.noProducts => l10n.billingUnavailableNoProducts(count: missingProducts),
        HeartUnavailableReason.serverStatus => l10n.billingUnavailableServerStatus,
      };
}

/// 결제 안내 두 줄(pen `bBjRD`) — 이 기기 스토어의 글자.
extension PaymentStoreText on PaymentStore {
  String paymentLine(AppLocalizations l10n) => switch (this) {
        PaymentStore.googlePlay => l10n.billingPaymentLineGooglePlay,
        PaymentStore.appStore => l10n.billingPaymentLineAppStore,
      };

  String refundLine(AppLocalizations l10n) => switch (this) {
        PaymentStore.googlePlay => l10n.billingRefundLineGooglePlay,
        PaymentStore.appStore => l10n.billingRefundLineAppStore,
      };
}

/// 번들 수량 · 가격 글자. 숫자 형식(천 단위 쉼표)은 [formatWon] 그대로다.
extension HeartBundleText on HeartBundle {
  /// "100하트".
  String quantityLabel(AppLocalizations l10n) => l10n.billingBundleQuantity(hearts: hearts);

  /// "5,700원" — 원화가 아니면 스토어 글자 그대로.
  String priceLabel(AppLocalizations l10n) {
    final won = price;
    return won == null ? storePriceLabel ?? '' : wonText(l10n, won);
  }
}

/// "6,000원" — 천 단위 쉼표 + 원.
String wonText(AppLocalizations l10n, int won) => l10n.billingWon(amount: formatWon(won));

/// 토스트 글자. 성공은 서버 숫자로(사용자 확정 10-13), 안내는 pen 글자.
String heartPurchaseToastText(AppLocalizations l10n, HeartPurchaseToast toast) => switch (toast) {
      GrantedToast(:final hearts, bonusHearts: 0) => l10n.billingToastGranted(hearts: hearts),
      GrantedToast(:final hearts, :final bonusHearts) =>
        l10n.billingToastGrantedWithBonus(total: hearts + bonusHearts, bonus: bonusHearts),
      NoticeToast(:final notice) => notice.title(l10n),
    };
