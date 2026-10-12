import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_mate/common/failure.dart';

/// 서버가 구매 실패 응답에 실어 보내는 기계용 `code`(backend `errors.py` CODE_HEARTS_NOT_ENOUGH · CODE_PAID_OFFER_GONE).
/// 앱은 이 code 로 먼저 가른다.
const String heartsNotEnoughCode = 'hearts_not_enough';
const String paidOfferGoneCode = 'paid_offer_gone';

/// 서버 `errors.py` 의 HEARTS_NOT_ENOUGH(402)와 같은 글자. code 를 주지 않는 옛 서버·다른 경로를 위한 폴백이다
/// (`ServerRejectedFailure` 에 상태코드가 없어 문구로 가른다).
const String heartsNotEnoughMessage = '하트가 모자라요';

/// 서버 `errors.py` 의 PAID_OFFER_GONE(409)와 같은 글자. 위와 같은 폴백이다.
const String paidOfferGoneMessage = '지금은 열 수 없는 카드예요';

/// 유료 카드 구매가 거절된 두 경우를 가른다(지시문 23 A3).
/// code 가 있으면 code 만 믿는다 — 모르는 code 는 문구가 맞아도 일반 실패다. code 가 없을 때만 문구로 가른다.
extension PaidPurchaseFailure on Failure {
  /// 402 — 하트가 모자라다. 하트 스토어로 보낸다.
  bool get isHeartsNotEnough => _is(heartsNotEnoughCode, heartsNotEnoughMessage);

  /// 409 — 제안이 이미 닫혔거나 상대가 자격을 잃었다. 화면을 새로 읽는다.
  bool get isPaidOfferGone => _is(paidOfferGoneCode, paidOfferGoneMessage);

  bool _is(String code, String message) {
    final failure = this;
    if (failure is! ServerRejectedFailure) {
      return false;
    }
    return failure.hasAnyCode() ? failure.hasCode(code) : failure.toDisplayMessage() == message;
  }
}

/// 서버가 문구까지 만들어 준 "맞는 이유" 한 줄(`reasons[]`). 앱이 문구를 만들지 않는다.
class ReasonTag {
  const ReasonTag({required this.kind, required this.text});

  /// 이유 종류(`tendency` · `tags` · `ideal` · `mbti` · `age_height` · `smoke_religion`). 앱은 가르지 않고 글자만 그린다.
  final String kind;
  final String text;

  /// 모양이 틀리면 null — 이유 한 줄이 틀렸다고 오늘 탭 전체를 죽이지 않는다.
  static ReasonTag? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final kind = json['kind'];
    final text = json['text'];
    return kind is String && text is String ? ReasonTag(kind: kind, text: text) : null;
  }

  /// `reasons` 칸이 없거나 null 이면 빈 목록이다(무료 카드 · 옛 서버). 모양이 틀린 항목은 건너뛴다.
  static List<ReasonTag> listFrom(Object? json) => [
        if (json is List<dynamic>)
          for (final item in json)
            if (tryParse(item) case final ReasonTag tag) tag,
      ];
}

/// `GET /cards/today` 의 `paid_card` — 결제 카드(잠금 카드) 자리에 무엇을 그릴지.
/// 없음(`null`)은 이 타입이 아니라 `TodayCards.paidCard == null` 로 나타낸다.
sealed class PaidCard {
  const PaidCard();

  /// 모르는 모양이면 null — 없는 것처럼 둔다(앱이 상태를 지어내지 않는다).
  static PaidCard? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    return switch (json['state']) {
      'offered' => PaidCardOffered.tryParse(json),
      'empty' => const PaidCardEmpty(),
      _ => null,
    };
  }
}

/// 지금 열 수 있는 한 사람이 정해져 있다(화면 `qoYnh`). 이름 · 학교 · 나이는 서버가 아예 안 준다.
final class PaidCardOffered extends PaidCard {
  const PaidCardOffered({
    required this.offerId,
    required this.bandCount,
    required this.reasons,
    required this.preview,
    required this.cost,
  });

  final String offerId;

  /// "나와 성향이 잘 맞는 사람 N명이 기다리고 있어요" 의 N.
  final int bandCount;
  final List<ReasonTag> reasons;

  /// 서버가 원본 아바타를 8×10 으로 줄여 준 JPEG(보안 점검 #3). 원본 주소는 결제 전에 아예 오지 않는다 —
  /// 주소에 상대 profile_id 가 있어 열면 얼굴이 보였다. 서버가 못 만들었으면 null(회색 원).
  final Uint8List? preview;

  /// 열 때 드는 하트. 버튼 글자 "N으로 열기" 의 N 이다.
  final int cost;

  /// 필수 칸(offer_id · band_count · cost)이 빠졌거나 모양이 틀리면 null — 결제 카드 없음으로 둔다.
  static PaidCardOffered? tryParse(Map<String, dynamic> json) {
    final offerId = json['offer_id'];
    final bandCount = json['band_count'];
    final cost = json['cost'];
    if (offerId is! String || bandCount is! int || cost is! int) {
      return null;
    }
    return PaidCardOffered(
      offerId: offerId,
      bandCount: bandCount,
      reasons: ReasonTag.listFrom(json['reasons']),
      preview: _decodePreview(json['preview']),
      cost: cost,
    );
  }

  /// base64 글자가 아니면 null — 미리보기 하나가 틀렸다고 결제 카드를 없애지 않는다.
  static Uint8List? _decodePreview(Object? value) {
    if (value is! String) {
      return null;
    }
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }
}

/// 후보는 있는데 지금 열 사람이 없다(화면 `SoMVZ`).
final class PaidCardEmpty extends PaidCard {
  const PaidCardEmpty();
}
