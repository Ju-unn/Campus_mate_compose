import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
