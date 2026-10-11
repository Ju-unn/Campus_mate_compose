import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/paid_card.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 계약(PR #440 `paid_card`)을 읽는 쪽의 방어. 모양이 틀린 결제 카드 하나가 오늘 탭 전체를 죽이면 안 된다.
void main() {
  group('PaidCard.tryParse', () {
    test('offered 의 필수 칸이 빠졌거나 모양이 틀리면 결제 카드 없음(null)이다 — 예외로 새지 않는다', () {
      for (final broken in <Map<String, dynamic>>[
        {'state': 'offered', 'band_count': 7, 'cost': 50},
        {'state': 'offered', 'offer_id': 'o', 'cost': 50},
        {'state': 'offered', 'offer_id': 'o', 'band_count': '7', 'cost': 50},
        {'state': 'offered', 'offer_id': 'o', 'band_count': 7},
      ]) {
        expect(PaidCard.tryParse(broken), isNull, reason: '$broken');
      }
    });

    test('Map 이 아니면 null 이다', () {
      expect(PaidCard.tryParse('offered'), isNull);
      expect(PaidCard.tryParse(7), isNull);
      expect(PaidCard.tryParse(null), isNull);
    });

    test('모양이 틀린 이유 항목은 건너뛰고 나머지를 읽는다', () {
      final paid = PaidCard.tryParse({
        'state': 'offered',
        'offer_id': 'o',
        'band_count': 3,
        'cost': 50,
        'reasons': [
          {'kind': 'tendency', 'text': '성향이 비슷해요'},
          {'kind': 'tags'},
          'oops',
        ],
      }) as PaidCardOffered;

      expect(paid.reasons.map((r) => r.text), ['성향이 비슷해요']);
    });
  });

  test('모양이 틀린 결제 카드가 있어도 오늘의 카드 목록은 그대로 읽힌다', () {
    final today = TodayCards.fromJson({
      'cards': <Object>[],
      'paid_card': {'state': 'offered'},
    });

    expect(today.paidCard, isNull);
  });

  group('PaidPurchaseFailure — 서버 문구로 402 · 409 를 가른다', () {
    test('서버가 거절한 두 문구만 맞고, 다른 실패는 둘 다 아니다', () {
      const short = ServerRejectedFailure(heartsNotEnoughMessage);
      const gone = ServerRejectedFailure(paidOfferGoneMessage);

      expect(short.isHeartsNotEnough, isTrue);
      expect(short.isPaidOfferGone, isFalse);
      expect(gone.isPaidOfferGone, isTrue);
      expect(gone.isHeartsNotEnough, isFalse);
      expect(const NetworkFailure().isHeartsNotEnough, isFalse);
      expect(const ServerRejectedFailure('다른 거절').isPaidOfferGone, isFalse);
    });

    test('서버가 code 를 주면 문구가 달라도 code 로 가른다', () {
      const short = ServerRejectedFailure('문구가 바뀌었어요', code: 'hearts_not_enough');
      const gone = ServerRejectedFailure('문구가 바뀌었어요', code: 'paid_offer_gone');

      expect(short.isHeartsNotEnough, isTrue);
      expect(short.isPaidOfferGone, isFalse);
      expect(gone.isPaidOfferGone, isTrue);
      expect(gone.isHeartsNotEnough, isFalse);
    });

    test('code 가 있으면 문구가 맞아도 code 를 따른다 — 모르는 code 는 일반 실패다', () {
      const unknown = ServerRejectedFailure(heartsNotEnoughMessage, code: 'something_else');
      const crossed = ServerRejectedFailure(heartsNotEnoughMessage, code: 'paid_offer_gone');

      expect(unknown.isHeartsNotEnough, isFalse);
      expect(unknown.isPaidOfferGone, isFalse);
      expect(crossed.isHeartsNotEnough, isFalse);
      expect(crossed.isPaidOfferGone, isTrue);
    });

    test('code 가 없는 옛 응답은 문구로 가른다', () {
      expect(const ServerRejectedFailure(heartsNotEnoughMessage).isHeartsNotEnough, isTrue);
      expect(const ServerRejectedFailure(paidOfferGoneMessage).isPaidOfferGone, isTrue);
    });

    test('문구가 서버 errors.py 와 같은 글자다', () {
      expect(heartsNotEnoughMessage, '하트가 모자라요');
      expect(paidOfferGoneMessage, '지금은 열 수 없는 카드예요');
    });
  });
}
