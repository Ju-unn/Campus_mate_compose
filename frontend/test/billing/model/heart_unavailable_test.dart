import 'package:campus_mate/billing/model/heart_unavailable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App Store 결제 불가 설명은 원인마다 다르다 — 사용자가 화면만 보고 어느 경우인지 안다', () {
    expect(
      const HeartUnavailable(HeartUnavailableReason.storeUnusable).appStoreCaption,
      '이 기기에서 App Store 결제를 쓸 수 없어요 · 설정 > 스크린 타임 > 콘텐츠 및 개인정보 보호 > iTunes 및 App Store 구입 > 앱 내 구입을 확인해 주세요',
    );
    expect(
      const HeartUnavailable(HeartUnavailableReason.noProducts, missingProducts: 5).appStoreCaption,
      '상품 정보를 불러오지 못했어요 · App Store 상품이 아직 준비 중일 수 있어요 (못 찾은 상품 5개)',
    );
    expect(
      const HeartUnavailable(HeartUnavailableReason.serverStatus).appStoreCaption,
      '서버에서 상태를 읽지 못했어요 · 잠시 뒤 다시 시도해 주세요',
    );
  });

  test('로그 글자는 원인 이름과 못 찾은 상품 개수를 담는다', () {
    expect(
      const HeartUnavailable(HeartUnavailableReason.noProducts, missingProducts: 5).logLine,
      '하트 상점 결제 불가: noProducts (못 찾은 상품 5개)',
    );
  });
}
