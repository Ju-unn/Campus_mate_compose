import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_chat_repository.dart';

void main() {
  final now = DateTime(2026, 9, 22, 12);
  final justMatched = now.subtract(const Duration(hours: 1));
  final aDayAgo = now.subtract(const Duration(hours: 25));

  ChatRoomUiState stateOf(ChatRoom room, {bool sheetDismissed = false}) =>
      ChatRoomUiState(isLoading: false, room: room, sheetDismissed: sheetDismissed);

  test('24시간 전에는 미리 수락 배너만 뜨고 시트는 뜨지 않는다', () {
    // 첫 인사를 하러 들어왔는데 카카오톡 아이디 시트가 덮으면 그게 첫 화면이 된다(결정 10).
    final state = stateOf(roomFixture(createdAt: justMatched));

    expect(state.stageAt(now), TrustGateStage.preAccept);
  });

  test('24시간이 지나고 아직 수락 안 했으면 시트가 뜬다', () {
    expect(stateOf(roomFixture(createdAt: aDayAgo)).stageAt(now), TrustGateStage.sheet);
  });

  test('시트를 닫으면 종료 예정 배너로 바뀐다', () {
    // 14h 의 조건이 "거절한 뒤" 에서 바뀌었다 — 결정 11 로 거절한 사람은 방을 떠난다.
    final state = stateOf(roomFixture(createdAt: aDayAgo), sheetDismissed: true);

    expect(state.stageAt(now), TrustGateStage.ending);
  });

  test('내가 수락했으면 기다림 배너다', () {
    final state = stateOf(roomFixture(createdAt: aDayAgo, myResponse: 'accept'));

    expect(state.stageAt(now), TrustGateStage.waiting);
  });

  test('통과했으면 시스템 카드다', () {
    expect(stateOf(roomFixture(passed: true)).stageAt(now), TrustGateStage.revealed);
  });

  test('상대가 나간 방에서는 배너도 시트도 안 뜬다', () {
    // 게이트가 멈춘다(결정 7). 24시간이 지났어도 마찬가지다.
    final state = stateOf(roomFixture(createdAt: aDayAgo, partnerLeft: true));

    expect(state.stageAt(now), TrustGateStage.none);
    expect(state.isPartnerGone, isTrue);
  });

  group('14b 카드 자리 시각(백로그 20)', () {
    final passedAt = DateTime(2026, 9, 22, 12, 30);
    Message accept(String id, DateTime at) =>
        messageFixture(id: id, kind: MessageKind.trustAccept, createdAt: at);

    test('두 번째 수락 줄이 도장보다 늦으면 그 줄 시각을 쓴다', () {
      final secondAccept = passedAt.add(const Duration(milliseconds: 40));
      final state = ChatRoomUiState(
        room: roomFixture(passed: true, passedAt: passedAt),
        messages: [accept('first', DateTime(2026, 9, 22, 9)), accept('second', secondAccept)],
      );

      expect(state.revealAnchorAt, secondAccept);
    });

    test('먼저 수락한 사람의 줄은 도장보다 이르니 도장 시각을 쓴다', () {
      final state = ChatRoomUiState(
        room: roomFixture(passed: true, passedAt: passedAt),
        messages: [accept('first', DateTime(2026, 9, 22, 9))],
      );

      expect(state.revealAnchorAt, passedAt);
    });

    test('통과 시각을 모르면 null 이다', () {
      final state = ChatRoomUiState(room: roomFixture(passed: true));

      expect(state.revealAnchorAt, isNull);
    });
  });

  group('상대가 아직 안 읽은 내 줄(카톡식 1, pen RvjRp Qs5As)', () {
    final readAt = DateTime(2026, 9, 22, 14, 12);
    final before = readAt.subtract(const Duration(minutes: 1));
    final after = readAt.add(const Duration(minutes: 1));
    ChatRoomUiState readState(PartnerRead read, {bool partnerLeft = false}) =>
        ChatRoomUiState(room: roomFixture(partnerLeft: partnerLeft), partnerRead: read);
    Message mine(DateTime at, {MessageKind kind = MessageKind.text}) =>
        messageFixture(senderId: myId, createdAt: at, kind: kind);

    test('읽은 시각보다 늦게 보낸 내 줄만 안 읽음이다(같은 시각은 읽음)', () {
      final state = readState(PartnerRead.known(readAt));

      expect(
        [state.isUnreadByPartner(mine(before)), state.isUnreadByPartner(mine(readAt)), state.isUnreadByPartner(mine(after))],
        [false, false, true],
      );
    });

    test('상대가 한 번도 안 읽었으면 내 줄 전부 안 읽음이다', () {
      expect(readState(const PartnerRead.known(null)).isUnreadByPartner(mine(before)), isTrue);
    });

    test('상대가 보낸 줄에는 없다', () {
      final state = readState(const PartnerRead.known(null));

      expect(state.isUnreadByPartner(messageFixture(senderId: partnerId, createdAt: after)), isFalse);
    });

    test('시스템 줄(내 수락 줄 포함)에는 없다', () {
      final state = readState(const PartnerRead.known(null));

      expect(state.isUnreadByPartner(mine(after, kind: MessageKind.trustAccept)), isFalse);
    });

    test('상대가 나간 방에는 없다 — 읽을 사람이 없다(대장 결정)', () {
      final state = readState(const PartnerRead.known(null), partnerLeft: true);

      expect(state.isUnreadByPartner(mine(after)), isFalse);
    });

    test('서버가 읽음 시각을 모르면(옛 서버) 없다', () {
      expect(readState(const PartnerRead.unknown()).isUnreadByPartner(mine(after)), isFalse);
    });

    test('방을 아직 못 읽었으면 없다', () {
      const state = ChatRoomUiState(partnerRead: PartnerRead.known(null));

      expect(state.isUnreadByPartner(mine(after)), isFalse);
    });

    test('copyWith 는 상대 읽음을 넘기지 않으면 그대로 둔다', () {
      final state = readState(PartnerRead.known(readAt)).copyWith(isSending: true);

      expect(state.isUnreadByPartner(mine(after)), isTrue);
      expect(state.isUnreadByPartner(mine(before)), isFalse);
    });
  });
}
