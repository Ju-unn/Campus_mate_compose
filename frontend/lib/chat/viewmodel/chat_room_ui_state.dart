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
    this.isDisconnected = false,
    this.errorMessage,
    this.partnerRead = const PartnerRead.unknown(),
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

  /// 실시간 통로가 끊겼다(백로그 19). 대화는 그대로 보이고 배너만 얹는다 —
  /// 보낸 메시지는 HTTP 로 가서 끊긴 동안에도 들어간다. 못 받는 것은 상대의 줄뿐이다.
  final bool isDisconnected;
  final String? errorMessage;

  /// 상대가 마지막으로 읽은 시각. 머리말 · 첫 페이지 · 2초 확인이 받은 값 중 **가장 늦은 것**이다.
  final PartnerRead partnerRead;

  bool get isEmpty => messages.isEmpty;

  /// 이 줄 옆에 안 읽음 '1' 을 그리는가(pen `RvjRp` 읽음 표시 `Qs5As`). **내가 보낸 text 줄마다 따로** 정한다.
  /// 상대 줄 · 시스템 줄에는 없고, 상대가 나간 방에서도 없다 — 읽을 사람이 없다(대장 결정 10-13).
  /// 보내는 중 · 실패한 글은 말풍선이 없어(서버가 돌려준 줄만 그린다) 여기까지 오지 않는다.
  bool isUnreadByPartner(Message message) {
    final room = this.room;
    if (room == null || message.isSystem || isPartnerGone || message.senderId == room.partner.profileId) {
      return false;
    }
    return partnerRead.hasNotRead(message.createdAt);
  }

  /// 입력창을 잠가야 하는 방(결정 7). 대화는 읽을 수 있지만 더 쓰지는 못한다.
  bool get isPartnerGone => room?.gate.partnerLeft ?? false;

  /// 14b 카드를 끼울 시각(백로그 20). 이 시각 **이하**의 줄 뒤에 온다.
  ///
  /// 통과 시각만 쓰면 카드가 두 번째 "수락했어요" 줄보다 위에 온다 — 서버 `/trust` 는 요청 시작
  /// 시각으로 도장을 찍고 **그 뒤에** 수락 줄을 DB 기본 시각으로 넣는다. 그래서 수락 줄 중 가장
  /// 늦은 것과 통과 시각 중 늦은 쪽을 쓴다. 통과 시각을 모르면 null(카드는 대화 끝).
  DateTime? get revealAnchorAt {
    final passedAt = room?.gate.passedAt;
    if (passedAt == null) {
      return null;
    }
    return messages
        .where((message) => message.kind == MessageKind.trustAccept)
        .map((message) => message.createdAt)
        .fold<DateTime>(passedAt, (latest, at) => at.isAfter(latest) ? at : latest);
  }

  /// 첫 입장 안내 카드(pen `cinKv`)를 대화 목록 맨 위에 끼우는가. **미리 수락 단계([TrustGateStage.preAccept] =
  /// 24시간 전 · 내가 아직 수락 전 · 공개 전 · 상대 있음) · 기한 전일 때만**(대장 결정 10-17). 카드 요약과 3번 항목이
  /// "위쪽의 '수락하기'"를 가리키는데 그 버튼은 미리 수락 배너에만 있다 — 14g · 시트 · 14h 단계에서는 숨긴다.
  bool showsIntroCardAt(DateTime now) =>
      stageAt(now) == TrustGateStage.preAccept && now.isBefore(room!.gate.deadlineAt);

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
    bool? isDisconnected,
    String? errorMessage,
    PartnerRead? partnerRead,
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
      isDisconnected: isDisconnected ?? this.isDisconnected,
      // 덮어쓰기다 — null 로도 지워져야 한다.
      errorMessage: errorMessage,
      partnerRead: partnerRead ?? this.partnerRead,
    );
  }
}
