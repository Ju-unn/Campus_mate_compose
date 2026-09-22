import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
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

  test('방을 못 읽으면 메시지도 읽지 않는다', () async {
    repository.room = const FailureResult(NotFoundFailure());

    final state = await opened(containerFor());

    expect(state.errorMessage, '요청한 정보를 찾을 수 없습니다');
    expect(repository.pages, isEmpty);
    expect(stream.subscribed, isEmpty);
  });
}
