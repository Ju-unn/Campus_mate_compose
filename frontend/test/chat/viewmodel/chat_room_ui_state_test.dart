import 'package:campus_mate/chat/model/chat_room.dart';
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
}
