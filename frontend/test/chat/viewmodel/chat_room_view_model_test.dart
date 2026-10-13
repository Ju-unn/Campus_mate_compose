import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/http_chat_repository.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/model/user_event_stream.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_view_model.dart';
import 'package:campus_mate/chat/viewmodel/user_channel.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show GoTrueClient, Session;

import '../model/fake_chat_repository.dart';

void main() {
  late FakeChatRepository repository;
  late FakeMessageStream stream;

  setUp(() {
    repository = FakeChatRepository()..room = Success(roomFixture());
    stream = FakeMessageStream();
  });

  ProviderContainer containerFor() {
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        messageStreamProvider.overrideWithValue(stream),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ChatRoomUiState> opened(ProviderContainer container) async {
    container.listen(chatRoomViewModelProvider('m1'), (_, _) {});
    // build() 의 microtask 가 끝나야 방·첫 페이지가 들어온다.
    await Future<void>.delayed(Duration.zero);
    return container.read(chatRoomViewModelProvider('m1'));
  }

  test('방을 열면 머리말·첫 50건을 읽고 읽음을 한 번 찍는다', () async {
    repository.messages = Success(MessagePage(messages: [messageFixture()], hasMore: false));

    final state = await opened(containerFor());

    expect(state.isLoading, isFalse);
    expect(state.messages.single.body, '안녕하세요');
    expect(repository.readCount, 1);
    expect(stream.subscribed, ['m1']);
  });

  test('구독이 준 줄이 목록 끝에 붙는다', () async {
    final container = containerFor();
    await opened(container);

    stream.push(messageFixture(id: 'msg-2', body: '반가워요'));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(chatRoomViewModelProvider('m1')).messages.last.body, '반가워요');
  });

  test('첫 페이지를 읽는 동안 구독으로 온 줄도 남는다', () async {
    final container = containerFor();
    // 구독이 먼저 걸려 있으니 조회가 끝나기 전에 줄이 올 수 있다 — 조회 결과가 그것을 덮으면 안 된다.
    repository.onFetchMessages = () => stream.push(messageFixture(id: 'msg-live', body: '먼저 왔어요'));

    await opened(container);
    await Future<void>.delayed(Duration.zero);

    final messages = container.read(chatRoomViewModelProvider('m1')).messages;
    expect(messages.map((message) => message.id), contains('msg-live'));
  });

  test('같은 줄이 두 번 와도 한 번만 그린다', () async {
    final container = containerFor();
    await opened(container);

    // 내가 보낸 줄은 응답으로도, 구독으로도 돌아온다.
    stream.push(messageFixture(id: 'msg-2'));
    stream.push(messageFixture(id: 'msg-2'));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(chatRoomViewModelProvider('m1')).messages.length, 1);
  });

  test('더 불러오기는 가장 오래된 줄을 커서로 보낸다', () async {
    repository.messages = Success(MessagePage(
      messages: [messageFixture(id: 'msg-1'), messageFixture(id: 'msg-2')],
      hasMore: true,
    ));
    final container = containerFor();
    await opened(container);

    await container.read(chatRoomViewModelProvider('m1').notifier).loadMore();

    expect(repository.pages.last.beforeId, 'msg-1');
    expect(repository.pages.last.before, messageFixture(id: 'msg-1').createdAt);
  });

  test('더 가져올 것이 없으면 요청하지 않는다', () async {
    final container = containerFor();
    await opened(container);
    final before = repository.pages.length;

    await container.read(chatRoomViewModelProvider('m1').notifier).loadMore();

    expect(repository.pages.length, before);
  });

  test('보내는 동안 잠기고 돌아온 줄이 목록에 붙는다', () async {
    repository.sendResult = Success(messageFixture(id: 'msg-9', senderId: myId, body: '네!'));
    final container = containerFor();
    await opened(container);

    await container.read(chatRoomViewModelProvider('m1').notifier).send('네!');
    final state = container.read(chatRoomViewModelProvider('m1'));

    expect(repository.sent, ['네!']);
    expect(state.isSending, isFalse);
    expect(state.messages.last.body, '네!');
  });

  test('보낸 줄이 구독으로 먼저 와도 응답 때문에 두 번 그려지지 않는다', () async {
    repository.sendResult = Success(messageFixture(id: 'msg-9', senderId: myId, body: '네!'));
    final container = containerFor();
    await opened(container);

    // 서버는 INSERT 뒤에 닉네임 조회·푸시를 하고 응답하므로 구독 줄이 먼저 오는 쪽이 정상이다.
    stream.push(messageFixture(id: 'msg-9', senderId: myId, body: '네!'));
    await Future<void>.delayed(Duration.zero);
    await container.read(chatRoomViewModelProvider('m1').notifier).send('네!');

    final messages = container.read(chatRoomViewModelProvider('m1')).messages;
    expect(messages.where((message) => message.id == 'msg-9').length, 1);
  });

  test('상대 줄이 구독으로 먼저 오고 내 응답이 늦게 와도 시간 · id 순으로 선다', () async {
    final base = DateTime(2026, 9, 22, 14, 10);
    // 서버는 내 INSERT(t1) 뒤에 닉네임 조회 · 푸시를 하고 응답한다 — 그 사이 상대 줄(t2)의 구독 줄이 응답보다 먼저 올 수 있다.
    repository.sendResult = Success(messageFixture(id: 'mine', senderId: myId, body: '내 글', createdAt: base));
    final container = containerFor();
    await opened(container);

    stream.push(messageFixture(id: 'theirs', body: '상대 글', createdAt: base.add(const Duration(milliseconds: 500))));
    await Future<void>.delayed(Duration.zero);
    await container.read(chatRoomViewModelProvider('m1').notifier).send('내 글');

    final bodies = container.read(chatRoomViewModelProvider('m1')).messages.map((message) => message.body).toList();
    expect(bodies, ['내 글', '상대 글']);
  });

  test('같은 시각이면 id 순으로 선다 — 서버 커서와 같다', () async {
    final base = DateTime(2026, 9, 22, 14, 10);
    final container = containerFor();
    await opened(container);

    stream.push(messageFixture(id: 'b', body: '둘째', createdAt: base));
    stream.push(messageFixture(id: 'a', body: '첫째', createdAt: base));
    await Future<void>.delayed(Duration.zero);

    final bodies = container.read(chatRoomViewModelProvider('m1')).messages.map((message) => message.body).toList();
    expect(bodies, ['첫째', '둘째']);
  });

  test('나가기가 끝나면 화면이 목록으로 돌아갈 준비를 한다', () async {
    final container = containerFor();
    await opened(container);

    await container.read(chatRoomViewModelProvider('m1').notifier).leave();

    expect(repository.leaveCount, 1);
    expect(container.read(chatRoomViewModelProvider('m1')).hasLeft, isTrue);
  });

  test('이미 나간 방이라는 409 도 나가기 성공으로 친다', () async {
    repository.writeResult = const FailureResult(ServerRejectedFailure('이미 나간 대화예요'));
    final container = containerFor();
    await opened(container);

    await container.read(chatRoomViewModelProvider('m1').notifier).leave();
    final state = container.read(chatRoomViewModelProvider('m1'));

    // 실패로 다루면 재시도한 사람이 방에 갇힌다.
    expect(state.hasLeft, isTrue);
    expect(state.errorMessage, isNull);
  });

  test('수락하면 방을 다시 읽어 카카오톡 아이디를 가져온다', () async {
    final container = containerFor();
    await opened(container);
    repository.trustResult = const Success(TrustAcceptOutcome(passed: true, kakaoId: 'fox_rain'));
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

    await container.read(chatRoomViewModelProvider('m1').notifier).acceptTrust();
    final state = container.read(chatRoomViewModelProvider('m1'));

    expect(repository.trustCount, 1);
    expect(state.room!.kakaoId, 'fox_rain');
    expect(state.stageAt(DateTime.now()), TrustGateStage.revealed);
  });

  test('방에 있는 동안 상대 수락 줄이 오면 머리말을 다시 읽어 통과를 반영한다', () async {
    // 두 번째 수락은 상대 화면에서 일어난다 — 구독으로 수락 줄만 오고 통과 카드·카카오톡 아이디는
    // 머리말을 다시 읽어야 내려온다(나갔다 들어와야 보이던 문제).
    final container = containerFor();
    await opened(container);
    expect(repository.roomFetchCount, 1);
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

    stream.push(messageFixture(id: 'accept-2', senderId: partnerId, kind: MessageKind.trustAccept));
    await Future<void>.delayed(Duration.zero);
    final state = container.read(chatRoomViewModelProvider('m1'));

    expect(repository.roomFetchCount, 2);
    expect(state.room!.gate.passed, isTrue);
    expect(state.room!.kakaoId, 'fox_rain');
  });

  test('방에 있는 동안 상대가 나가면 머리말을 다시 읽어 입력창을 잠근다(결함 A12)', () async {
    // 구독으로는 나감 줄만 온다 — 머리말을 안 읽으면 입력창이 남고 보내면 409(E-CHAT-61).
    final container = containerFor();
    await opened(container);
    repository.room = Success(roomFixture(partnerLeft: true));

    stream.push(messageFixture(id: 'left-1', kind: MessageKind.left, body: '여우비님이 채팅방을 나갔어요'));
    await Future<void>.delayed(Duration.zero);

    expect(repository.roomFetchCount, 2);
    expect(container.read(chatRoomViewModelProvider('m1')).isPartnerGone, isTrue);
  });

  test('머리말을 읽은 뒤 구독 전에 상대가 나갔으면 첫 페이지의 나감 줄을 보고 머리말을 다시 읽는다', () async {
    repository.messages = Success(MessagePage(
      messages: [messageFixture(id: 'left-1', kind: MessageKind.left, body: '여우비님이 채팅방을 나갔어요')],
      hasMore: false,
    ));
    repository.onFetchMessages = () => repository.room = Success(roomFixture(partnerLeft: true));
    final container = containerFor();

    await opened(container);
    await Future<void>.delayed(Duration.zero);

    expect(repository.roomFetchCount, 2);
    expect(container.read(chatRoomViewModelProvider('m1')).isPartnerGone, isTrue);
  });

  test('상대 수락 줄로 다시 읽다 실패해도 오류 줄을 띄우지 않는다', () async {
    // 사용자가 누른 것이 아니라 할 수 있는 일이 없다 — 방은 옛 머리말 그대로 둔다.
    final container = containerFor();
    await opened(container);
    repository.room = const FailureResult(NetworkFailure());

    stream.push(messageFixture(id: 'accept-2', senderId: partnerId, kind: MessageKind.trustAccept));
    await Future<void>.delayed(Duration.zero);
    final state = container.read(chatRoomViewModelProvider('m1'));

    expect(repository.roomFetchCount, 2);
    expect(state.errorMessage, isNull);
    expect(state.room, isNotNull);
  });

  test('상대 수락 줄로 다시 읽는 동안 뜬 오류 줄은 지우지 않는다', () async {
    final container = containerFor();
    await opened(container);
    final viewModel = container.read(chatRoomViewModelProvider('m1').notifier);
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
    repository.holdRoom = Completer<void>();

    stream.push(messageFixture(id: 'accept-2', senderId: partnerId, kind: MessageKind.trustAccept));
    await Future<void>.delayed(Duration.zero);
    // 다시 읽는 사이에 보내기가 실패했다.
    repository.sendResult = const FailureResult(NetworkFailure());
    await viewModel.send('안녕');
    final shown = container.read(chatRoomViewModelProvider('m1')).errorMessage;
    expect(shown, isNotNull);
    repository.holdRoom!.complete();
    await Future<void>.delayed(Duration.zero);
    final state = container.read(chatRoomViewModelProvider('m1'));

    expect(state.room!.gate.passed, isTrue);
    expect(state.errorMessage, shown);
  });

  test('구독 전에 들어온 상대 수락 줄이 첫 페이지에 있으면 머리말을 조용히 다시 읽는다', () async {
    // 방을 읽은 직후 상대가 두 번째로 수락하면 그 줄은 구독이 아니라 첫 페이지로 들어온다.
    repository.room = Success(roomFixture(myResponse: 'accept'));
    repository.messages = Success(MessagePage(
      messages: [messageFixture(id: 'accept-2', senderId: partnerId, kind: MessageKind.trustAccept)],
      hasMore: false,
    ));
    repository.onFetchMessages = () =>
        repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

    final container = containerFor();
    await opened(container);
    await Future<void>.delayed(Duration.zero);
    final state = container.read(chatRoomViewModelProvider('m1'));

    expect(repository.roomFetchCount, 2);
    expect(state.room!.gate.passed, isTrue);
  });

  test('상대만 먼저 수락한 방에 들어올 때는 머리말을 다시 읽지 않는다', () async {
    // 내가 수락하지 않았으면 상대 수락 줄로 통과될 수 없다 — 들어올 때마다 헛요청을 보내지 않는다.
    repository.messages = Success(MessagePage(
      messages: [messageFixture(id: 'accept-2', senderId: partnerId, kind: MessageKind.trustAccept)],
      hasMore: false,
    ));

    await opened(containerFor());
    await Future<void>.delayed(Duration.zero);

    expect(repository.roomFetchCount, 1);
  });

  test('내 수락 줄은 머리말을 다시 읽지 않는다 — 수락 응답 뒤에 이미 읽는다', () async {
    final container = containerFor();
    await opened(container);

    stream.push(messageFixture(id: 'accept-1', senderId: myId, kind: MessageKind.trustAccept));
    await Future<void>.delayed(Duration.zero);

    expect(repository.roomFetchCount, 1);
  });

  test('이미 통과한 방에서는 수락 줄이 와도 머리말을 다시 읽지 않는다', () async {
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
    final container = containerFor();
    await opened(container);

    stream.push(messageFixture(id: 'accept-2', senderId: partnerId, kind: MessageKind.trustAccept));
    await Future<void>.delayed(Duration.zero);

    expect(repository.roomFetchCount, 1);
  });

  test('수락 중에 예외가 나도 다시 누를 수 있다', () async {
    // 보내는 중 표시가 굳으면 그 방에서는 다시 수락할 길이 없다.
    final container = containerFor();
    await opened(container);
    repository.throwOnTrust = true;
    final viewModel = container.read(chatRoomViewModelProvider('m1').notifier);

    await expectLater(viewModel.acceptTrust(), throwsStateError);

    repository.throwOnTrust = false;
    repository.trustResult = const Success(TrustAcceptOutcome(passed: true, kakaoId: 'fox_rain'));
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
    await viewModel.acceptTrust();

    expect(repository.trustCount, 2);
    expect(container.read(chatRoomViewModelProvider('m1')).room!.kakaoId, 'fox_rain');
  });

  test('기한이 지났다는 409 는 종료 안내와 같은 문구로 보여준다', () async {
    repository.trustResult = const FailureResult(ServerRejectedFailure('응답 기한이 지났어요'));
    final container = containerFor();
    await opened(container);

    await container.read(chatRoomViewModelProvider('m1').notifier).acceptTrust();

    expect(
      container.read(chatRoomViewModelProvider('m1')).errorMessage,
      '응답 기한이 지나 이 대화는 종료됐어요',
    );
  });

  test('구독이 끊기면 배너 표시만 켜고 대화는 그대로 둔다', () async {
    repository.messages = Success(MessagePage(messages: [messageFixture()], hasMore: false));
    final container = containerFor();
    await opened(container);

    stream.pushError();
    await Future<void>.delayed(Duration.zero);

    final state = container.read(chatRoomViewModelProvider('m1'));
    expect(state.isDisconnected, isTrue);
    expect(state.messages, hasLength(1));
  });

  test('다시 시도하면 구독을 새로 걸고 못 받은 줄을 가져온다', () async {
    repository.messages = Success(MessagePage(messages: [messageFixture(id: 'msg-1')], hasMore: false));
    final container = containerFor();
    await opened(container);
    stream.pushError();
    await Future<void>.delayed(Duration.zero);

    // 끊긴 동안 들어온 줄은 구독으로는 영영 오지 않는다 — 재조회가 데려와야 한다.
    repository.messages = Success(MessagePage(
      messages: [messageFixture(id: 'msg-1'), messageFixture(id: 'msg-2', body: '그동안 온 줄')],
      hasMore: false,
    ));

    await container.read(chatRoomViewModelProvider('m1').notifier).reconnect();
    final state = container.read(chatRoomViewModelProvider('m1'));

    expect(state.isDisconnected, isFalse);
    expect(state.messages.map((message) => message.id), ['msg-1', 'msg-2']);
    expect(stream.subscribed, ['m1', 'm1']);
  });

  test('끊겼던 통로가 스스로 다시 붙으면 배너를 내리고 끊긴 동안 온 줄을 다시 읽는다(결함 A12)', () async {
    repository.messages = Success(MessagePage(messages: [messageFixture(id: 'msg-1')], hasMore: false));
    final container = containerFor();
    await opened(container);
    stream.pushError();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(chatRoomViewModelProvider('m1')).isDisconnected, isTrue);

    repository.messages = Success(MessagePage(
      messages: [messageFixture(id: 'msg-1'), messageFixture(id: 'msg-2', body: '그동안 온 줄')],
      hasMore: false,
    ));
    stream.rejoin();
    await Future<void>.delayed(Duration.zero);
    final state = container.read(chatRoomViewModelProvider('m1'));

    expect(state.isDisconnected, isFalse);
    expect(state.messages.map((message) => message.id), ['msg-1', 'msg-2']);
    expect(repository.roomFetchCount, 2);
  });

  test('다시 연결한 뒤 옛 구독이 늦게 "다시 붙음" 을 알려도 또 다시 읽지 않는다', () async {
    final container = containerFor();
    await opened(container);
    await container.read(chatRoomViewModelProvider('m1').notifier).reconnect();
    final fetches = repository.roomFetchCount;

    stream.rejoin(subscription: 0);
    await Future<void>.delayed(Duration.zero);

    expect(stream.subscribed, ['m1', 'm1']);
    expect(repository.roomFetchCount, fetches);
  });

  test('이미 나간 방을 열면 첫 페이지에 나감 줄이 있어도 머리말을 한 번만 읽는다', () async {
    repository
      ..room = Success(roomFixture(partnerLeft: true))
      ..messages = Success(MessagePage(
        messages: [messageFixture(id: 'left-1', kind: MessageKind.left, body: '여우비님이 채팅방을 나갔어요')],
        hasMore: false,
      ));

    await opened(containerFor());
    await Future<void>.delayed(Duration.zero);

    expect(repository.roomFetchCount, 1);
  });

  test('다시 시도는 머리말도 다시 읽는다', () async {
    final container = containerFor();
    await opened(container);

    // 끊긴 사이에 상대가 나갔다. 머리말을 안 읽으면 입력창이 열린 채로 남아 보내기가 409 로 막힌다.
    repository.room = Success(roomFixture(partnerLeft: true));
    await container.read(chatRoomViewModelProvider('m1').notifier).reconnect();

    expect(container.read(chatRoomViewModelProvider('m1')).isPartnerGone, isTrue);
  });

  test('재연결 때 머리말 뒤 첫 페이지에 상대 수락 줄이 있으면 머리말을 조용히 다시 읽는다', () async {
    // 머리말을 읽은 직후 상대가 두 번째로 수락하면 그 줄은 재조회 첫 페이지로만 들어온다.
    repository.room = Success(roomFixture(myResponse: 'accept'));
    final container = containerFor();
    await opened(container);
    expect(repository.roomFetchCount, 1);
    repository.messages = Success(MessagePage(
      messages: [messageFixture(id: 'accept-2', senderId: partnerId, kind: MessageKind.trustAccept)],
      hasMore: false,
    ));
    repository.onFetchMessages = () =>
        repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

    await container.read(chatRoomViewModelProvider('m1').notifier).reconnect();
    await Future<void>.delayed(Duration.zero);

    // 재연결 머리말 1 + 병합 뒤 검사 1.
    expect(repository.roomFetchCount, 3);
    expect(container.read(chatRoomViewModelProvider('m1')).room!.gate.passed, isTrue);
  });

  test('재연결 재조회가 위로 올려 읽어 둔 옛 줄보다 앞에 끼어들지 않는다', () async {
    final older = messageFixture(id: 'msg-0', createdAt: DateTime(2026, 9, 22, 9));
    final newer = messageFixture(id: 'msg-5', createdAt: DateTime(2026, 9, 22, 15));
    repository.messages = Success(MessagePage(messages: [older], hasMore: false));
    final container = containerFor();
    await opened(container);

    repository.messages = Success(MessagePage(messages: [newer], hasMore: false));
    await container.read(chatRoomViewModelProvider('m1').notifier).reconnect();

    // 새로 읽은 50건을 앞에 그냥 붙이면 옛 줄이 아래로 내려간다.
    expect(
      container.read(chatRoomViewModelProvider('m1')).messages.map((message) => message.id),
      ['msg-0', 'msg-5'],
    );
  });

  test('방을 못 읽으면 메시지도 읽지 않는다', () async {
    repository.room = const FailureResult(NotFoundFailure());

    final state = await opened(containerFor());

    expect(state.errorMessage, '요청한 정보를 찾을 수 없습니다');
    expect(repository.pages, isEmpty);
    expect(stream.subscribed, isEmpty);
  });

  // E-CHAT-67 — 서버는 postgres_changes 복제를 join 성공 뒤에 비동기로 만든다. "첫 페이지를 읽은 시점 ~ 복제가 살기 전"
  // 사이에 들어온 글은 첫 읽기도 구독도 못 받는다. 구독이 "준비됨" 을 알리면 첫 페이지를 조용히 한 번 더 읽어 합친다.
  group('구독이 준비됐다고 알리면(ready)', () {
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    ChatRoomUiState read(ProviderContainer container) => container.read(chatRoomViewModelProvider('m1'));

    test('첫 페이지를 읽은 뒤 저장소에 생긴 글이 합쳐진다 — 구독으로는 오지 않았다', () async {
      repository.messages = Success(MessagePage(messages: [messageFixture(id: 'msg-1')], hasMore: false));
      final container = containerFor();
      await opened(container);

      repository.messages = Success(MessagePage(
        messages: [messageFixture(id: 'msg-1'), messageFixture(id: 'msg-2', body: '놓친 줄', createdAt: DateTime(2026, 9, 22, 14, 11))],
        hasMore: false,
      ));
      stream.ready();
      await settle();

      expect(read(container).messages.map((message) => message.id), ['msg-1', 'msg-2']);
      // 다시 구독하지도, 머리말을 다시 읽지도 않는다 — reconnect 를 부르면 다시 구독 → 다시 붙음이 끝없이 돈다.
      expect(stream.subscribed, ['m1']);
      expect(repository.roomFetchCount, 1);
    });

    test('이미 있는 글은 두 번 그리지 않는다 — 신호가 겹쳐 와도 마찬가지다', () async {
      repository.messages = Success(MessagePage(messages: [messageFixture(id: 'msg-1')], hasMore: false));
      final container = containerFor();
      await opened(container);
      stream.push(messageFixture(id: 'msg-2', createdAt: DateTime(2026, 9, 22, 14, 11)));
      await settle();

      repository.messages = Success(MessagePage(
        messages: [messageFixture(id: 'msg-1'), messageFixture(id: 'msg-2', createdAt: DateTime(2026, 9, 22, 14, 11))],
        hasMore: false,
      ));
      stream
        ..ready()
        ..ready();
      await settle();

      expect(read(container).messages.map((message) => message.id), ['msg-1', 'msg-2']);
    });

    test('위로 올려 읽어 둔 옛 줄과 hasMore 를 지우지 않는다', () async {
      final oldest = messageFixture(id: 'msg-0', createdAt: DateTime(2026, 9, 22, 9));
      final middle = messageFixture(id: 'msg-5', createdAt: DateTime(2026, 9, 22, 15));
      repository.messages = Success(MessagePage(messages: [middle], hasMore: true));
      final container = containerFor();
      await opened(container);
      repository.messages = Success(MessagePage(messages: [oldest], hasMore: false));
      await container.read(chatRoomViewModelProvider('m1').notifier).loadMore();
      expect(read(container).hasMore, isFalse);

      // 첫 페이지 결과의 hasMore 는 "더 옛 줄이 있다" 라고 말하지만, 이미 끝까지 올려 읽었다.
      repository.messages = Success(MessagePage(
        messages: [middle, messageFixture(id: 'msg-6', createdAt: DateTime(2026, 9, 22, 16))],
        hasMore: true,
      ));
      stream.ready();
      await settle();

      expect(read(container).messages.map((message) => message.id), ['msg-0', 'msg-5', 'msg-6']);
      expect(read(container).hasMore, isFalse);
    });

    test('읽기 실패는 오류 줄을 띄우지 않고 가진 글을 그대로 둔다', () async {
      repository.messages = Success(MessagePage(messages: [messageFixture(id: 'msg-1')], hasMore: false));
      final container = containerFor();
      await opened(container);

      repository.messages = const FailureResult(NetworkFailure());
      stream.ready();
      await settle();

      expect(read(container).errorMessage, isNull);
      expect(read(container).isLoading, isFalse);
      expect(read(container).messages.map((message) => message.id), ['msg-1']);
    });

    test('읽기에 성공해도 떠 있던 오류 줄은 지우지 않는다 — 조용한 재조회다', () async {
      final container = containerFor();
      await opened(container);
      repository.sendResult = const FailureResult(NetworkFailure());
      await container.read(chatRoomViewModelProvider('m1').notifier).send('안녕');
      expect(read(container).errorMessage, '네트워크 연결을 확인해 주세요');

      repository.messages = Success(MessagePage(messages: [messageFixture(id: 'msg-2')], hasMore: false));
      stream.ready();
      await settle();

      expect(read(container).errorMessage, '네트워크 연결을 확인해 주세요');
      expect(read(container).messages.map((message) => message.id), ['msg-2']);
    });

    test('다시 연결한 뒤 옛 구독이 늦게 알리는 준비됨은 무시한다', () async {
      final container = containerFor();
      await opened(container);
      await container.read(chatRoomViewModelProvider('m1').notifier).reconnect();
      final fetches = repository.pages.length;
      repository.messages = Success(MessagePage(messages: [messageFixture(id: 'late')], hasMore: false));

      stream.ready(subscription: 0);
      await settle();

      expect(repository.pages.length, fetches);
      expect(read(container).messages, isEmpty);
    });

    test('화면을 닫은 뒤의 준비됨은 아무것도 읽지 않는다', () async {
      final container = containerFor();
      await opened(container);
      final fetches = repository.pages.length;
      container.dispose();

      stream.ready();
      await settle();

      expect(repository.pages.length, fetches);
    });

    test('읽는 도중에 화면이 닫혀도 닫힌 뒤에는 상태를 건드리지 않는다', () async {
      final container = containerFor();
      await opened(container);
      repository.messages = Success(MessagePage(messages: [messageFixture(id: 'late')], hasMore: false));
      repository.onFetchMessages = container.dispose; // 요청이 나간 뒤 응답이 오기 전에 닫힌다

      stream.ready();
      await settle();

      // 닫힌 Notifier 에 state 를 쓰면 던진다 — 던졌다면 이 시험이 처리 안 된 오류로 실패한다.
      expect(repository.pages, hasLength(2));
    });

    test('합친 줄이 상대의 두 번째 수락이면 머리말을 조용히 다시 읽는다', () async {
      repository.room = Success(roomFixture(myResponse: 'accept'));
      final container = containerFor();
      await opened(container);
      expect(repository.roomFetchCount, 1);
      repository.messages = Success(MessagePage(
        messages: [messageFixture(id: 'accept-2', kind: MessageKind.trustAccept)],
        hasMore: false,
      ));
      repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

      stream.ready();
      await settle();

      expect(repository.roomFetchCount, 2);
      expect(read(container).room!.gate.passed, isTrue);
    });

    test('합친 줄이 상대의 나감이면 머리말을 다시 읽어 입력창을 잠근다', () async {
      final container = containerFor();
      await opened(container);
      repository.messages = Success(MessagePage(
        messages: [messageFixture(id: 'left-1', kind: MessageKind.left, body: '여우비님이 채팅방을 나갔어요')],
        hasMore: false,
      ));
      repository.room = Success(roomFixture(partnerLeft: true));

      stream.ready();
      await settle();

      expect(repository.roomFetchCount, 2);
      expect(read(container).isPartnerGone, isTrue);
    });
  });

  // 카톡식 '1'(사용자 결정 10-13). 상대 읽음 확인([partnerReadPollFast])과 읽음 묶음은 시계가 아니라 Timer 로 돈다 —
  // testWidgets 의 가짜 시간으로 실제로 기다리지 않고 넘긴다.
  group('상대 읽음 확인과 읽음 묶음', () {
    final sentAt = DateTime(2026, 10, 13, 14, 15);
    final readAfter = PartnerRead.known(sentAt.add(const Duration(seconds: 1)));
    Message mine([String id = 'mine-1']) => messageFixture(id: id, senderId: myId, createdAt: sentAt);
    Message theirs(String id) => messageFixture(id: id, createdAt: sentAt);

    /// 방을 열고 첫 페이지까지 들어오게 한다. 시험 끝에 컨테이너를 닫아 남은 Timer 를 지운다.
    /// [live] 는 사용자 채널(`user:<내 id>`)이 붙어 있는가 — 붙었으면 확인이 느려진다.
    Future<ProviderContainer> openRoom(WidgetTester tester, {List<Message>? messages, bool live = false}) async {
      repository.room = Success(roomFixture(partnerRead: const PartnerRead.known(null)));
      repository.messages = Success(MessagePage(messages: messages ?? [mine()], hasMore: false));
      final container = ProviderContainer(overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        messageStreamProvider.overrideWithValue(stream),
        userChannelProvider.overrideWith(() => FakeUserChannel(initiallyLive: live)),
      ]);
      addTearDown(container.dispose);
      container.listen(chatRoomViewModelProvider('m1'), (_, _) {});
      await tester.pump();
      await tester.pump();
      return container;
    }

    ChatRoomUiState stateOf(ProviderContainer container) => container.read(chatRoomViewModelProvider('m1'));
    ChatRoomViewModel viewModelOf(ProviderContainer container) =>
        container.read(chatRoomViewModelProvider('m1').notifier);
    bool hasUnread(ProviderContainer container) =>
        stateOf(container).messages.any(stateOf(container).isUnreadByPartner);

    test('확인 간격은 사용자 채널이 안 붙었으면 2초(사용자 요청 10-13), 붙었으면 30초 안전망이다(설계안 A)', () {
      expect(partnerReadPollFast, const Duration(seconds: 2));
      expect(partnerReadPollSlow, const Duration(seconds: 30));
    });

    // 사용자 채널이 실제로 붙었을 때(SUBSCRIBED)만 느리게 — 정책 적용 전(입장 거부)에 앱을 먼저 배포해도 지금과 같은 체감이다.
    testWidgets('사용자 채널이 붙어 있으면 30초마다만 묻는다', (tester) async {
      final container = await openRoom(tester, live: true);

      await tester.pump(partnerReadPollSlow - const Duration(milliseconds: 1));
      expect(repository.partnerReadFetchCount, 0);
      await tester.pump(const Duration(milliseconds: 1));

      expect(repository.partnerReadFetchCount, 1);
      container.dispose();
    });

    testWidgets('사용자 채널이 끊기면 바로 한 번 묻고 2초 간격으로 돌아간다 — 다시 붙으면 30초로', (tester) async {
      final container = await openRoom(tester, live: true);
      final channel = container.read(userChannelProvider.notifier) as FakeUserChannel;

      channel.setLive(false);
      await tester.pump();
      expect(repository.partnerReadFetchCount, 1);
      await tester.pump(partnerReadPollFast);
      expect(repository.partnerReadFetchCount, 2);

      channel.setLive(true);
      await tester.pump();
      expect(repository.partnerReadFetchCount, 3);
      await tester.pump(partnerReadPollFast * 3);
      expect(repository.partnerReadFetchCount, 3);
      container.dispose();
    });

    testWidgets('안 보이는 동안 채널 상태가 바뀌어도 묻지 않는다', (tester) async {
      final container = await openRoom(tester, live: true);
      viewModelOf(container).setVisible(false);

      (container.read(userChannelProvider.notifier) as FakeUserChannel).setLive(false);
      await tester.pump(partnerReadPollFast * 3);

      expect(repository.partnerReadFetchCount, 0);
      container.dispose();
    });

    testWidgets('read 이벤트가 오면 폴링을 기다리지 않고 내 줄의 1 이 바로 사라진다', (tester) async {
      final container = await openRoom(tester, live: true);
      expect(hasUnread(container), isTrue);

      viewModelOf(container).receivePartnerRead(ReadEvent('m1', readerId: partnerId, readAt: sentAt.add(const Duration(seconds: 1))));
      await tester.pump();

      expect(hasUnread(container), isFalse);
      expect(repository.partnerReadFetchCount, 0);
      container.dispose();
    });

    // 서버 읽음 시각은 +09:00, 방 응답은 +00:00 으로 올 수 있다 — 시각을 순간으로 비교해야 늦은 값이 이긴다.
    testWidgets('늦게 온 옛 read 이벤트는 1 을 되살리지 않는다 — 오프셋이 달라도 순간으로 비교한다', (tester) async {
      final container = await openRoom(tester, live: true);
      // 내 줄보다 5분 늦은 읽음은 +09:00 으로, 5분 이른 읽음은 +00:00(Z) 으로 적힌 문자열에서 읽는다.
      String kst(DateTime at) => '${at.toUtc().add(const Duration(hours: 9)).toIso8601String().replaceFirst('Z', '')}+09:00';
      final later = DateTime.parse(kst(sentAt.add(const Duration(minutes: 5))));
      final earlier = DateTime.parse(sentAt.subtract(const Duration(minutes: 5)).toUtc().toIso8601String());

      viewModelOf(container).receivePartnerRead(ReadEvent('m1', readerId: partnerId, readAt: later));
      viewModelOf(container).receivePartnerRead(ReadEvent('m1', readerId: partnerId, readAt: earlier));
      await tester.pump();

      expect(hasUnread(container), isFalse);
      container.dispose();
    });

    testWidgets('상대가 아닌 사람의 읽음 · 다른 방의 읽음은 쓰지 않는다', (tester) async {
      final container = await openRoom(tester, live: true);
      final readAt = sentAt.add(const Duration(seconds: 1));

      viewModelOf(container).receivePartnerRead(ReadEvent('m1', readerId: myId, readAt: readAt));
      viewModelOf(container).receivePartnerRead(ReadEvent('m2', readerId: partnerId, readAt: readAt));
      await tester.pump();

      expect(hasUnread(container), isTrue);
      container.dispose();
    });

    testWidgets('사용자 채널로 온 이 방의 줄은 방 채널과 겹쳐도 한 번만 붙고, 지금 보이는지 알려 준다', (tester) async {
      final container = await openRoom(tester);

      stream.push(theirs('t1'));
      await tester.pump();
      final seen = viewModelOf(container).receiveFromUserChannel(theirs('t1'));
      await tester.pump();

      expect(seen, isTrue);
      expect(stateOf(container).messages.where((message) => message.id == 't1'), hasLength(1));

      viewModelOf(container).setVisible(false);
      expect(viewModelOf(container).receiveFromUserChannel(theirs('t2')), isFalse);
      container.dispose();
    });

    testWidgets('사용자 채널로만 온 상대 줄도 방에 붙고 읽음을 찍는다(방 채널 복제가 늦을 때)', (tester) async {
      final container = await openRoom(tester);
      expect(repository.readCount, 1);

      viewModelOf(container).receiveFromUserChannel(theirs('t1'));
      await tester.pump();

      expect(stateOf(container).messages.map((message) => message.id), contains('t1'));
      expect(repository.readCount, 2);
      container.dispose();
    });

    testWidgets('방이 보이는 동안 2초마다 상대 읽음을 묻고, 읽었으면 1 이 사라진다', (tester) async {
      final container = await openRoom(tester);
      expect(hasUnread(container), isTrue);

      await tester.pump(partnerReadPollFast - const Duration(milliseconds: 1));
      expect(repository.partnerReadFetchCount, 0);
      repository.partnerReadResult = Success(readAfter);
      await tester.pump(const Duration(milliseconds: 1));

      expect(repository.partnerReadFetchCount, 1);
      expect(hasUnread(container), isFalse);
      container.dispose();
    });

    testWidgets('메시지 목록은 건드리지 않고 방 머리말도 다시 읽지 않는다', (tester) async {
      final container = await openRoom(tester);
      final pagesBefore = repository.pages.length;

      await tester.pump(partnerReadPollFast * 2);

      expect((repository.partnerReadFetchCount, repository.pages.length, repository.roomFetchCount), (2, pagesBefore, 1));
      container.dispose();
    });

    testWidgets('안 읽은 내 줄이 없으면 묻지 않는다', (tester) async {
      final container = await openRoom(tester, messages: [theirs('t1')]);

      await tester.pump(partnerReadPollFast * 3);

      expect(repository.partnerReadFetchCount, 0);
      container.dispose();
    });

    testWidgets('앞 확인이 안 끝났으면 겹쳐 부르지 않는다', (tester) async {
      final container = await openRoom(tester);
      repository.holdPartnerRead = Completer<void>();

      await tester.pump(partnerReadPollFast * 3);
      expect(repository.partnerReadFetchCount, 1);

      repository.holdPartnerRead!.complete();
      await tester.pump(partnerReadPollFast);
      expect(repository.partnerReadFetchCount, 2);
      container.dispose();
    });

    testWidgets('확인이 실패하면 조용히 넘어가고 떠 있던 오류 줄도 그대로 둔다', (tester) async {
      final container = await openRoom(tester);
      repository.sendResult = const FailureResult(NetworkFailure());
      await viewModelOf(container).send('안녕');
      final error = stateOf(container).errorMessage;
      expect(error, isNotNull);

      repository.partnerReadResult = const FailureResult(NetworkFailure());
      await tester.pump(partnerReadPollFast);
      expect((stateOf(container).errorMessage, hasUnread(container)), (error, true));

      repository.partnerReadResult = Success(readAfter);
      await tester.pump(partnerReadPollFast);
      expect((stateOf(container).errorMessage, hasUnread(container)), (error, false));
      container.dispose();
    });

    testWidgets('늦게 도착한 옛 읽음 값이 새 값을 덮어 1 을 되살리지 않는다', (tester) async {
      final container = await openRoom(tester);
      repository.partnerReadResult = Success(readAfter);
      await tester.pump(partnerReadPollFast);
      expect(hasUnread(container), isFalse);

      // 재연결이 읽은 머리말 · 첫 페이지가 그보다 이른 값(한 번도 안 읽음)을 들고 왔다.
      repository.room = Success(roomFixture(partnerRead: const PartnerRead.known(null)));
      repository.messages = Success(MessagePage(messages: [mine()], hasMore: false, partnerRead: const PartnerRead.known(null)));
      await viewModelOf(container).reconnect();

      expect(hasUnread(container), isFalse);
      container.dispose();
    });

    testWidgets('안 보이면(백그라운드 · 다른 화면) 멈추고, 다시 보이면 바로 한 번 묻고 이어 간다', (tester) async {
      final container = await openRoom(tester);
      viewModelOf(container).setVisible(false);

      await tester.pump(partnerReadPollFast * 4);
      expect(repository.partnerReadFetchCount, 0);

      viewModelOf(container).setVisible(true);
      await tester.pump();
      expect(repository.partnerReadFetchCount, 1);

      await tester.pump(partnerReadPollFast);
      expect(repository.partnerReadFetchCount, 2);
      container.dispose();
    });

    testWidgets('방을 닫으면 확인이 멈춘다', (tester) async {
      final container = await openRoom(tester);
      container.dispose();

      await tester.pump(partnerReadPollFast * 4);

      expect(repository.partnerReadFetchCount, 0);
    });

    testWidgets('방을 보는 동안 받은 상대 줄은 읽음으로 찍되 3초에 한 번으로 묶는다', (tester) async {
      final container = await openRoom(tester);
      expect(repository.readCount, 1);

      stream.push(theirs('t1'));
      await tester.pump();
      expect(repository.readCount, 2);

      stream.push(theirs('t2'));
      await tester.pump(const Duration(milliseconds: 500));
      stream.push(theirs('t3'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.readCount, 2);

      await tester.pump(const Duration(seconds: 2));
      expect(repository.readCount, 3);

      await tester.pump(const Duration(seconds: 10));
      expect(repository.readCount, 3);
      container.dispose();
    });

    testWidgets('내 줄이 돌아올 때는 읽음을 찍지 않는다', (tester) async {
      final container = await openRoom(tester);

      stream.push(mine('mine-2'));
      await tester.pump(const Duration(seconds: 5));

      expect(repository.readCount, 1);
      container.dispose();
    });

    testWidgets('안 보이는 동안 온 상대 줄은 찍지 않고, 다시 보이면 찍는다', (tester) async {
      final container = await openRoom(tester);
      viewModelOf(container).setVisible(false);

      stream.push(theirs('t1'));
      await tester.pump(const Duration(seconds: 5));
      expect(repository.readCount, 1);

      viewModelOf(container).setVisible(true);
      await tester.pump();
      expect(repository.readCount, 2);
      container.dispose();
    });

    testWidgets('다시 연결하면(앱 복귀 · 다시 시도) 읽음을 찍는다', (tester) async {
      final container = await openRoom(tester);

      await viewModelOf(container).reconnect();
      await tester.pump();

      expect(repository.readCount, 2);
      container.dispose();
    });

    // 10-13 아이폰: 방에 들어올 때 찍는 읽음이 끝내 안 돌아오면 확인이 영영 시작되지 않았다(그 방문 내내 '1' 이 남는다).
    // 가짜 저장소는 요청이 걸리는 일이 없다 — 실제 HTTP 저장소 · ApiClient 를 지나게 한다.
    testWidgets('들어올 때 찍는 읽음(PATCH)이 끝내 안 돌아와도, 시간 제한 뒤 상대 읽음 확인이 시작된다', (tester) async {
      var partnerReadCalls = 0;
      final client = MockClient((request) {
        final path = request.url.path;
        if (request.method == 'PATCH') return Completer<http.Response>().future;
        if (path == '/chat/conversations') return Future.value(_json({'conversations': <Object>[]}));
        if (path == '/chat/matches/m1') return Future.value(_json(_roomJson));
        if (request.url.queryParameters['limit'] == '1') {
          partnerReadCalls += 1;
          return Future.value(_json({'messages': <Object>[], 'has_more': true, 'partner_last_read_at': null}));
        }
        return Future.value(_json({'messages': [_myMessageJson], 'has_more': false, 'partner_last_read_at': null}));
      });
      final auth = _MockGoTrueClient();
      final session = _MockSession();
      when(() => session.accessToken).thenReturn('token');
      when(() => auth.currentSession).thenReturn(session);
      final container = ProviderContainer(overrides: [
        chatRepositoryProvider.overrideWithValue(HttpChatRepository(ApiClient('https://api.test', client, auth))),
        messageStreamProvider.overrideWithValue(stream),
      ]);
      addTearDown(container.dispose);
      container.listen(chatRoomViewModelProvider('m1'), (_, _) {});
      await tester.pump();
      await tester.pump();
      expect(hasUnread(container), isTrue);

      await tester.pump(partnerReadPollFast * 3);
      expect(partnerReadCalls, 0, reason: '읽음 찍기가 걸린 동안');

      await tester.pump(readTimeout + partnerReadPollFast);
      expect(partnerReadCalls, greaterThanOrEqualTo(1), reason: '걸린 읽음 찍기가 끊긴 뒤');
      container.dispose();
    });
  });
}

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

const _roomJson = {
  'match_id': 'm1',
  'created_at': '2026-10-13T14:00:00+09:00',
  'chat_closed_at': null,
  'my_last_read_at': null,
  'partner': {'profile_id': 'p2', 'nickname': '여우비', 'avatar_url': null},
  'gate': {
    'my_response': null,
    'passed': false,
    'partner_left': false,
    'deadline_at': '2026-10-15T14:00:00+09:00',
    'remaining_seconds': 172800,
  },
};

const _myMessageJson = {
  'id': 'mine-1',
  'sender_id': 'me',
  'kind': 'text',
  'body': '안녕하세요',
  'created_at': '2026-10-13T14:15:00+09:00',
};

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSession extends Mock implements Session {}
