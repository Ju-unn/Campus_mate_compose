import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/model/message_stream.dart';
import 'package:campus_mate/common/result.dart';

/// 화면·ViewModel 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeChatRepository implements ChatRepository {
  Result<List<Conversation>> conversations = const Success([]);
  Result<ChatRoom>? room;
  Result<MessagePage> messages = const Success(MessagePage(messages: [], hasMore: false));
  Result<Message?> sendResult = const Success(null);
  Result<void> writeResult = const Success(null);
  Result<TrustAcceptOutcome> trustResult = const Success(TrustAcceptOutcome(passed: false));

  final List<String> sent = [];
  final List<({DateTime? before, String? beforeId})> pages = [];
  int readCount = 0;
  int leaveCount = 0;
  int trustCount = 0;

  /// 응답을 읽다 터지는 경우. `Result` 로 감싸지지 않고 그대로 올라온다.
  bool throwOnTrust = false;

  /// 조회 중에 구독 줄이 들어오는 상황을 만들 때 쓴다.
  void Function()? onFetchMessages;

  @override
  Future<Result<List<Conversation>>> fetchConversations() async => conversations;

  @override
  Future<Result<ChatRoom>> fetchRoom(String matchId) async => room!;

  @override
  Future<Result<MessagePage>> fetchMessages(
    String matchId, {
    DateTime? before,
    String? beforeId,
  }) async {
    pages.add((before: before, beforeId: beforeId));
    onFetchMessages?.call();
    return messages;
  }

  @override
  Future<Result<Message?>> sendMessage(String matchId, String body) async {
    sent.add(body);
    return sendResult;
  }

  @override
  Future<Result<void>> markRead(String matchId) async {
    readCount += 1;
    return writeResult;
  }

  @override
  Future<Result<void>> leave(String matchId) async {
    leaveCount += 1;
    return writeResult;
  }

  @override
  Future<Result<TrustAcceptOutcome>> acceptTrust(String matchId) async {
    trustCount += 1;
    if (throwOnTrust) {
      throw StateError('boom');
    }
    return trustResult;
  }
}

const String partnerId = 'p2';
const String myId = 'p1';

/// 방 하나. 기본은 **매칭한 지 얼마 안 된 · 아무도 수락하지 않은** 상태다.
ChatRoom roomFixture({
  DateTime? createdAt,
  String? myResponse,
  bool passed = false,
  bool partnerLeft = false,
  String? kakaoId,
  String? myKakaoId,
  List<String> photoUrls = const [],
}) {
  final created = createdAt ?? DateTime.now();
  return ChatRoom(
    matchId: 'm1',
    partner: const ChatPartner(profileId: partnerId, nickname: '여우비'),
    createdAt: created,
    gate: TrustGate(
      passed: passed,
      partnerLeft: partnerLeft,
      deadlineAt: created.add(trustGateDeadline),
      myResponse: myResponse,
    ),
    kakaoId: kakaoId,
    myKakaoId: myKakaoId,
    photoUrls: photoUrls,
  );
}

Message messageFixture({
  String id = 'msg-1',
  String senderId = partnerId,
  MessageKind kind = MessageKind.text,
  String body = '안녕하세요',
  DateTime? createdAt,
}) {
  return Message(
    id: id,
    senderId: senderId,
    body: body,
    kind: kind,
    createdAt: createdAt ?? DateTime(2026, 9, 22, 14, 10),
  );
}

Conversation conversationFixture({
  String matchId = 'm1',
  String nickname = '여우비',
  String? lastMessage = '내일 시간 괜찮으세요?',
  MessageKind? lastMessageKind = MessageKind.text,
  int unreadCount = 0,
}) {
  return Conversation(
    matchId: matchId,
    partner: ChatPartner(profileId: partnerId, nickname: nickname),
    lastMessageAt: DateTime(2026, 9, 22, 14, 14),
    unreadCount: unreadCount,
    trustPassed: false,
    remainingSeconds: 3600,
    lastMessage: lastMessage,
    lastMessageKind: lastMessageKind,
  );
}

/// Supabase Realtime 자리에 끼우는 가짜. [push] 로 새 메시지가 온 것처럼 만든다.
class FakeMessageStream implements MessageStream {
  final StreamController<Message> _controller = StreamController<Message>.broadcast();
  final List<String> subscribed = [];
  bool isClosed = false;

  @override
  Stream<Message> subscribe(String matchId) {
    subscribed.add(matchId);
    return _controller.stream.doOnCancel(() => isClosed = true);
  }

  void push(Message message) => _controller.add(message);

  /// 통로가 끊긴 상황(백로그 19). 실제 구현은 Realtime 의 channelError·timedOut 을 이렇게 올린다.
  void pushError() => _controller.addError(StateError('realtime channelError'));
}

extension _CancelHook<T> on Stream<T> {
  /// 구독이 끊겼는지 보려고 쓴다 — `StreamController.broadcast` 는 onCancel 이 늦게 불려서
  /// 화면이 닫혔는지 확인하려면 구독 쪽에 걸어야 한다.
  Stream<T> doOnCancel(void Function() onCancel) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      onListen: () => subscription = listen(controller.add, onError: controller.addError),
      onCancel: () {
        onCancel();
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
