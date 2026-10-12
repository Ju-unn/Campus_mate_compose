import 'package:campus_mate/matching/model/sent_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GET /cards/sent` 한 줄. 서버는 상대 profile_id 를 싣지 않는다(router.py `del card["profile_id"]`).
Map<String, dynamic> sentJson({
  String status = 'waiting',
  int? daysLeft = 3,
  String? matchId,
}) =>
    {
      'card_id': 'card-1',
      'status': status,
      'sent_at': '2026-10-13T10:00:00+00:00',
      'expires_at': '2026-10-20T10:00:00+00:00',
      'days_left': daysLeft,
      'resolved_at': null,
      'match_id': matchId,
      'profile': {
        'nickname': '여우비',
        'age': 23,
        'university': '테스트대학교',
        'major': '컴퓨터공학과',
        'avatar_url': null,
      },
    };

void main() {
  test('기다리는 중은 남은 날을 읽고 방은 없다', () {
    final request = SentRequest.fromJson(sentJson(daysLeft: 3));

    expect(request.cardId, 'card-1');
    expect(request.status, SentRequestStatus.waiting);
    expect(request.daysLeft, 3);
    expect(request.matchId, isNull);
    expect(request.opensChat, isFalse);
  });

  test('profile_id 가 없어도 닉네임 · 나이 · 학교 줄을 읽는다', () {
    final request = SentRequest.fromJson(sentJson());

    expect(request.profile.profileId, isNull);
    expect(request.profile.nameWithAge, '여우비, 23');
    expect(request.profile.schoolLine, '테스트대학교 · 컴퓨터공학과');
    expect(request.profile.avatarUrl, isNull);
  });

  test('매칭됨이고 방이 있으면 대화방을 연다', () {
    final request = SentRequest.fromJson(sentJson(status: 'matched', daysLeft: null, matchId: 'm-1'));

    expect(request.status, SentRequestStatus.matched);
    expect(request.daysLeft, isNull);
    expect(request.matchId, 'm-1');
    expect(request.opensChat, isTrue);
  });

  test('매칭됨인데 방 id 가 null 이면 열지 않는다', () {
    final request = SentRequest.fromJson(sentJson(status: 'matched', daysLeft: null));

    expect(request.opensChat, isFalse);
  });

  test('거절됨 · 만료됨은 남은 날도 방도 없고 열지 않는다', () {
    for (final (wire, status) in [('rejected', SentRequestStatus.rejected), ('expired', SentRequestStatus.expired)]) {
      final request = SentRequest.fromJson(sentJson(status: wire, daysLeft: null));

      expect(request.status, status, reason: wire);
      expect(request.daysLeft, isNull, reason: wire);
      expect(request.opensChat, isFalse, reason: wire);
    }
  });
}
