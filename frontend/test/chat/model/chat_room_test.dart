import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:flutter_test/flutter_test.dart';

/// 방 머리말 응답(서버 `GET /chat/matches/{id}`)의 최소 모양.
Map<String, dynamic> roomJson([Map<String, dynamic> extra = const {}]) => {
      'match_id': 'm1',
      'partner': {'profile_id': 'p2', 'nickname': '여우비', 'avatar_url': null},
      'created_at': '2026-10-13T05:00:00Z',
      'gate': {'passed': false, 'partner_left': false, 'deadline_at': '2026-10-15T05:00:00Z'},
      ...extra,
    };

void main() {
  // 서버는 UTC 로 준다. 비교는 같은 시각끼리라 지역 시간대와 상관없다.
  final readAt = DateTime.parse('2026-10-13T05:15:00.123456Z');

  group('상대 읽음(카톡식 1) — 키 없음 · null · 값을 따로 읽는다', () {
    test('키가 없으면(옛 서버) 어떤 줄도 안 읽음으로 보지 않는다 — 1 을 그리지 않는다', () {
      final room = ChatRoom.fromJson(roomJson());

      expect(room.partnerRead.hasNotRead(DateTime.parse('2030-01-01T00:00:00Z')), isFalse);
    });

    test('키가 있고 null 이면 상대가 한 번도 안 읽었다 — 내 줄 전부 안 읽음', () {
      final room = ChatRoom.fromJson(roomJson({'partner_last_read_at': null}));

      expect(room.partnerRead.hasNotRead(DateTime.parse('2000-01-01T00:00:00Z')), isTrue);
    });

    test('값이 있으면 그보다 늦은 줄만 안 읽음이고, 같은 시각은 읽은 것이다', () {
      final room = ChatRoom.fromJson(roomJson({'partner_last_read_at': '2026-10-13T05:15:00.123456Z'}));

      expect(room.partnerRead.hasNotRead(readAt.subtract(const Duration(microseconds: 1))), isFalse);
      expect(room.partnerRead.hasNotRead(readAt), isFalse);
      expect(room.partnerRead.hasNotRead(readAt.add(const Duration(microseconds: 1))), isTrue);
    });

    test('메시지 목록 응답도 같은 키를 같은 규칙으로 읽는다', () {
      MessagePage page(Map<String, dynamic> extra) =>
          MessagePage.fromJson({'messages': [], 'has_more': false, ...extra});
      final later = readAt.add(const Duration(seconds: 1));

      expect(page({}).partnerRead.hasNotRead(later), isFalse);
      expect(page({'partner_last_read_at': null}).partnerRead.hasNotRead(later), isTrue);
      expect(page({'partner_last_read_at': '2026-10-13T05:15:00.123456Z'}).partnerRead.hasNotRead(later), isTrue);
      expect(page({'partner_last_read_at': '2026-10-13T05:15:00.123456Z'}).partnerRead.hasNotRead(readAt), isFalse);
    });
  });

  group('두 응답을 합칠 때는 늦게 읽은 쪽이 남는다 — 늦게 도착한 옛 값이 1 을 되살리지 않게', () {
    final earlier = PartnerRead.known(readAt.subtract(const Duration(minutes: 1)));
    final newer = PartnerRead.known(readAt);
    final probe = readAt.subtract(const Duration(seconds: 30));

    test('더 늦은 시각이 이긴다(어느 쪽에서 불러도)', () {
      expect(earlier.later(newer).hasNotRead(probe), isFalse);
      expect(newer.later(earlier).hasNotRead(probe), isFalse);
    });

    test('한 번도 안 읽음(null)은 어떤 시각보다 이르다', () {
      expect(const PartnerRead.known(null).later(newer).hasNotRead(probe), isFalse);
      expect(newer.later(const PartnerRead.known(null)).hasNotRead(probe), isFalse);
    });

    test('키 없는 응답은 아는 값을 지우지 않고, 아는 값은 키 없음을 대신한다', () {
      expect(newer.later(const PartnerRead.unknown()).hasNotRead(probe), isFalse);
      expect(const PartnerRead.unknown().later(const PartnerRead.known(null)).hasNotRead(probe), isTrue);
    });
  });
}
