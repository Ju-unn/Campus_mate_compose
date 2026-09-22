import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/message.dart';

/// 신뢰 확인 게이트가 방 위에 무엇을 띄우는가(결정 10·11).
enum TrustGateStage {
  /// 아무것도 안 띄운다 — 상대가 나간 방(게이트가 멈춘다).
  none,

  /// 24시간 전. **미리 수락 배너만** 띄우고 시트는 띄우지 않는다.
  /// 첫 인사를 하러 들어왔는데 카카오톡 아이디 시트가 덮으면 그게 첫 화면이 된다.
  preAccept,

  /// 24시간 뒤 미수락. 방에 들어올 때마다 14f 시트가 뜬다.
  sheet,

  /// 시트를 닫고 계속 볼 때. 14h "이 대화는 N시간 뒤 종료돼요".
  ending,

  /// 내가 수락하고 상대를 기다리는 중. 14g 배너.
  waiting,

  /// 양쪽 수락 완료. 14b 시스템 카드.
  revealed,
}

/// 채팅방(화면 14)의 상태.
class ChatRoomUiState {
  const ChatRoomUiState({
    this.isLoading = true,
    this.room,
    this.messages = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isSending = false,
    this.hasLeft = false,
    this.sheetDismissed = false,
    this.errorMessage,
  });

  final bool isLoading;
  final ChatRoom? room;

  /// **오래된 것부터** 담겨 있다. 화면은 이 순서 그대로 아래로 쌓는다.
  final List<Message> messages;
  final bool hasMore;
  final bool isLoadingMore;

  /// 보내는 중. 버튼만 잠그고 목록은 건드리지 않는다.
  final bool isSending;

  /// 나가기가 끝났다. 화면은 목록으로 돌아간다.
  final bool hasLeft;

  /// 이번 방문에 14f 시트를 닫았다. 다시 들어오면 또 뜬다(설계 §2.5).
  final bool sheetDismissed;
  final String? errorMessage;

  bool get isEmpty => messages.isEmpty;

  /// 입력창을 잠가야 하는 방(결정 7). 대화는 읽을 수 있지만 더 쓰지는 못한다.
  bool get isPartnerGone => room?.gate.partnerLeft ?? false;

  TrustGateStage stageAt(DateTime now) {
    final room = this.room;
    if (room == null) {
      return TrustGateStage.none;
    }
    final gate = room.gate;
    if (gate.passed) {
      return TrustGateStage.revealed;
    }
    // 상대가 나가면 게이트가 멈춘다 — 배너도 시트도 뜨지 않는다(결정 7).
    if (gate.partnerLeft) {
      return TrustGateStage.none;
    }
    if (gate.accepted) {
      return TrustGateStage.waiting;
    }
    if (!room.isReminderDue(now)) {
      return TrustGateStage.preAccept;
    }
    return sheetDismissed ? TrustGateStage.ending : TrustGateStage.sheet;
  }

  /// **[errorMessage] 만 규칙이 다르다** — 넘기지 않으면 유지가 아니라 지워진다.
  /// 오류 문구는 "다음 동작이 시작되면 사라져야" 하는 값이라 그 편이 부르는 쪽 실수가 적다.
  /// 대신 문구를 남겨 둔 채 다른 칸만 바꾸고 싶다면 `errorMessage` 를 다시 실어야 한다.
  ChatRoomUiState copyWith({
    bool? isLoading,
    ChatRoom? room,
    List<Message>? messages,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isSending,
    bool? hasLeft,
    bool? sheetDismissed,
    String? errorMessage,
  }) {
    return ChatRoomUiState(
      isLoading: isLoading ?? this.isLoading,
      room: room ?? this.room,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSending: isSending ?? this.isSending,
      hasLeft: hasLeft ?? this.hasLeft,
      sheetDismissed: sheetDismissed ?? this.sheetDismissed,
      // 덮어쓰기다 — null 로도 지워져야 한다.
      errorMessage: errorMessage,
    );
  }
}
