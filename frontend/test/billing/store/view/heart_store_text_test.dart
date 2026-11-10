import 'package:campus_mate/billing/store/model/data/heart_bundles.dart';
import 'package:campus_mate/billing/store/model/data/heart_purchase_notice.dart';
import 'package:campus_mate/billing/store/model/data/heart_unavailable.dart';
import 'package:campus_mate/billing/store/model/data/payment_store.dart';
import 'package:campus_mate/billing/store/model/data/store_purchase.dart';
import 'package:campus_mate/billing/store/view/heart_store_text.dart';
import 'package:campus_mate/billing/store/viewmodel/heart_purchase_ui_state.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

/// 하트 상점 화면 글자(문구 파일 ARB, 1.0.2 B8). enum · 번들 · 토스트는 종류만 들고 글자는 view 쪽 확장이 정한다.
void main() {
  final l10n = AppLocalizationsKo();

  group('결제 안내 · 오류(HeartPurchaseNotice)', () {
    test('문구는 pen 15e-8 `JGoPI` 여덟 개와 글자까지 같다(환불 안내는 pen 에 없다 — 아래)', () {
      expect(
        [
          for (final notice in HeartPurchaseNotice.values.where((n) => n != HeartPurchaseNotice.revoked))
            (notice.name, notice.title(l10n), notice.caption(l10n)),
        ],
        [
          ('canceled', '결제를 취소했어요', null),
          ('alreadyProcessed', '이미 처리된 결제예요', null),
          ('pending', '결제 확인을 기다리고 있어요', '확인되면 하트가 들어와요'),
          ('delayed', '하트 지급이 늦어지고 있어요', '앱을 다시 열면 이어서 들어와요'),
          ('failed', '결제가 되지 않았어요', '결제 수단을 확인하고 다시 시도해 주세요'),
          ('invalid', '결제를 확인하지 못했어요', '문제가 계속되면 appmailerl4538@gmail.com으로 알려 주세요'),
          ('otherAccount', '다른 계정으로 결제한 하트예요', '결제한 계정으로 로그인하면 들어와요'),
          ('unavailable', '지금은 하트를 살 수 없어요', '구글 플레이에 로그인했는지 확인해 주세요'),
        ],
      );
    });

    test('환불된 애플 거래(422 purchase_revoked) 안내는 짧은 토스트 "환불된 결제예요"(pen 후속)', () {
      expect((HeartPurchaseNotice.revoked.title(l10n), HeartPurchaseNotice.revoked.caption(l10n)), ('환불된 결제예요', null));
    });

    test('설명이 있는 안내만 배너다 — 토스트 셋은 설명이 없다', () {
      for (final notice in HeartPurchaseNotice.values) {
        expect(notice.caption(l10n) != null, notice.isBanner, reason: notice.name);
      }
    });

    test('스토어 이름이 든 설명은 결제 불가 하나 — App Store 는 원인 중립 문구(pen 후속), 나머지는 두 스토어가 같다', () {
      // 아이폰 결제 불가의 원인은 로그인이 아니라 기기의 앱 내 구입 제한 · 상품 미등록 · 심사 전이다.
      expect(
        HeartPurchaseNotice.unavailable.captionOn(l10n, PaymentStore.appStore),
        '이 기기에서 App Store 결제를 쓸 수 없거나 상품을 불러오지 못했어요',
      );
      expect(HeartPurchaseNotice.unavailable.captionOn(l10n, PaymentStore.googlePlay), '구글 플레이에 로그인했는지 확인해 주세요');
      for (final notice in HeartPurchaseNotice.values.where((n) => n != HeartPurchaseNotice.unavailable)) {
        expect(notice.captionOn(l10n, PaymentStore.appStore), notice.caption(l10n), reason: notice.name);
      }
    });
  });

  test('App Store 결제 불가 설명은 원인마다 다르다 — 사용자가 화면만 보고 어느 경우인지 안다', () {
    expect(
      const HeartUnavailable(HeartUnavailableReason.storeUnusable).appStoreCaption(l10n),
      '이 기기에서 App Store 결제를 쓸 수 없어요 · 설정 > 스크린 타임 > 콘텐츠 및 개인정보 보호 > iTunes 및 App Store 구입 > 앱 내 구입을 확인해 주세요',
    );
    expect(
      const HeartUnavailable(HeartUnavailableReason.noProducts, missingProducts: 5).appStoreCaption(l10n),
      '상품 정보를 불러오지 못했어요 · App Store 상품이 아직 준비 중일 수 있어요 (못 찾은 상품 5개)',
    );
    expect(
      const HeartUnavailable(HeartUnavailableReason.serverStatus).appStoreCaption(l10n),
      '서버에서 상태를 읽지 못했어요 · 잠시 후 다시 시도해 주세요',
    );
  });

  group('결제 안내 두 줄(PaymentStore)', () {
    test('구글은 pen `bBjRD` 글자 그대로, App Store 는 같은 꼴에 스토어 이름만 바꾼다(pen 후속)', () {
      expect([for (final store in PaymentStore.values) (store.name, store.paymentLine(l10n), store.refundLine(l10n))], [
        ('googlePlay', '결제는 구글 플레이로 처리돼요', '결제 취소 · 환불은 구글 플레이 환불 절차를 따라요'),
        ('appStore', '결제는 App Store로 처리돼요', '결제 취소 · 환불은 App Store 환불 절차를 따라요'),
      ]);
    });

    test('App Store 문구에도 하네스 금지어(환급 · 선물 · 송금 · 현금 · 출금)가 없다(E-HEART-49)', () {
      final lines = [for (final store in PaymentStore.values) ...[store.paymentLine(l10n), store.refundLine(l10n)]];
      for (final word in ['환급', '선물', '송금', '현금', '출금']) {
        expect(lines.where((line) => line.contains(word)), isEmpty, reason: word);
      }
    });
  });

  group('번들 글자(HeartBundle)', () {
    final hundred = heartBundles[defaultHeartBundleIndex];

    test('수량은 "100하트", 원화 가격은 천 단위 쉼표 + "원"', () {
      expect((hundred.quantityLabel(l10n), hundred.priceLabel(l10n)), ('100하트', '5,700원'));
      expect(heartBundles.last.withStorePrice(const StorePrice(label: '₩38,400', won: 38400)).priceLabel(l10n), '38,400원');
    });

    test('원화가 아니면 스토어 글자 그대로', () {
      expect(hundred.withStorePrice(const StorePrice(label: r'US$4.99')).priceLabel(l10n), r'US$4.99');
    });
  });

  test('토스트 글자 — 성공은 서버 숫자로(사용자 확정 10-13), 안내는 pen 글자', () {
    expect(heartPurchaseToastText(l10n, const GrantedToast(hearts: 100, bonusHearts: 50)), '150하트가 들어왔어요(보너스 50 포함)');
    expect(heartPurchaseToastText(l10n, const GrantedToast(hearts: 800, bonusHearts: 0)), '800하트가 들어왔어요');
    expect(heartPurchaseToastText(l10n, const NoticeToast(HeartPurchaseNotice.alreadyProcessed)), '이미 처리된 결제예요');
  });
}
