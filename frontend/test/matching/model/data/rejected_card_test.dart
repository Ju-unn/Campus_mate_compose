import 'package:campus_mate/matching/model/data/rejected_card.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GET /cards/rejected` 한 줄. 서버는 상대 profile_id 를 싣지 않는다(router.py `del card["profile_id"]`).
Map<String, dynamic> rejectedJson({
  String cardId = 'card-1',
  String source = 'card',
  int daysLeft = 6,
  String? university = '테스트대학교',
  String? avatarUrl,
}) =>
    {
      'card_id': cardId,
      'source': source,
      'rejected_at': '2026-11-20T10:00:00+00:00',
      'expires_at': '2026-11-27T10:00:00+00:00',
      'days_left': daysLeft,
      'profile': {
        'nickname': '여우비',
        'age': 23,
        'university': university,
        'major': null,
        'avatar_url': avatarUrl,
      },
    };

void main() {
  group('RejectedCard', () {
    test('내 카드 거절 줄은 다시 신청 종류다', () {
      final card = RejectedCard.fromJson(rejectedJson(source: 'card', daysLeft: 6));

      expect(card.cardId, 'card-1');
      expect(card.source, RejectedSource.card);
      expect(card.daysLeft, 6);
      expect(card.profile.nameWithAge, '여우비, 23');
    });

    test('받은 신청 거절 줄은 되돌리기 종류다', () {
      final card = RejectedCard.fromJson(rejectedJson(source: 'acceptance'));

      expect(card.source, RejectedSource.acceptance);
    });

    test('학교 · 학과 · 아바타가 null 이어도 읽는다 — 학교 줄은 있는 것만', () {
      final card = RejectedCard.fromJson(rejectedJson(university: null));

      expect(card.profile.schoolLine, '');
      expect(card.profile.avatarUrl, isNull);
      expect(card.profile.profileId, isNull);
    });
  });

  group('RejectedCards', () {
    test('서버 순서 그대로 담는다(최신 거절 먼저)', () {
      final cards = RejectedCards.fromJson({
        'rejected': [rejectedJson(cardId: 'a'), rejectedJson(cardId: 'b', source: 'acceptance')],
      });

      expect(cards.toList().map((card) => card.cardId), ['a', 'b']);
      expect(cards.isEmpty, isFalse);
    });

    test('모르는 source 줄은 건너뛰고 나머지는 남는다 — 서버가 종류를 늘려도 목록이 죽지 않는다', () {
      final cards = RejectedCards.fromJson({
        'rejected': [rejectedJson(cardId: 'a', source: 'poll'), rejectedJson(cardId: 'b')],
      });

      expect(cards.toList().map((card) => card.cardId), ['b']);
    });

    test('빈 목록이면 비었다', () {
      expect(RejectedCards.fromJson({'rejected': <dynamic>[]}).isEmpty, isTrue);
      expect(RejectedCards.empty.isEmpty, isTrue);
    });

    test('without 은 그 줄만 뺀 새 목록이다 — 원래 목록은 그대로', () {
      final cards = RejectedCards.fromJson({
        'rejected': [rejectedJson(cardId: 'a'), rejectedJson(cardId: 'b')],
      });

      final rest = cards.without('a');

      expect(rest.toList().map((card) => card.cardId), ['b']);
      expect(cards.toList(), hasLength(2));
    });

    test('find 는 그 줄을 찾고 없으면 null 이다', () {
      final cards = RejectedCards.fromJson({'rejected': [rejectedJson(cardId: 'a')]});

      expect(cards.find('a')!.profile.nickname, '여우비');
      expect(cards.find('zz'), isNull);
    });
  });
}
