import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/chat/view/system_message.dart';
import 'package:campus_mate/chat/view/trust_reveal_bubble.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
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

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        messageStreamProvider.overrideWithValue(stream),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChatRoomScreen(matchId: 'm1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('상대 말풍선과 내 말풍선을 함께 그린다', (tester) async {
    repository.messages = Success(MessagePage(
      messages: [
        messageFixture(id: 'a', senderId: partnerId, body: '안녕하세요'),
        messageFixture(id: 'b', senderId: myId, body: '반가워요'),
      ],
      hasMore: false,
    ));

    await pump(tester);

    expect(find.text('여우비'), findsOneWidget);
    // 내 id 를 따로 들고 다니지 않는다 — 상대가 아니면 내 것이다.
    final bubbles = {
      for (final bubble in tester.widgetList<MessageBubble>(find.byType(MessageBubble)))
        bubble.message.body: bubble.isMine,
    };
    expect(bubbles, {'안녕하세요': false, '반가워요': true});
  });

  testWidgets('시스템 줄은 말풍선으로 그리지 않는다', (tester) async {
    repository.messages = Success(MessagePage(
      messages: [messageFixture(kind: MessageKind.left, body: '여우비님이 채팅방을 나갔어요')],
      hasMore: false,
    ));

    await pump(tester);

    expect(find.byType(SystemMessage), findsOneWidget);
    expect(find.byType(MessageBubble), findsNothing);
  });

  testWidgets('상대가 나간 방에서는 입력 바 대신 안내가 뜬다', (tester) async {
    // 눌러도 아무 일 없는 칸을 남겨 두지 않는다(결정 7).
    repository.room = Success(roomFixture(partnerLeft: true));

    await pump(tester);

    expect(find.text('상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('빈 입력으로는 보낼 수 없고 글자를 넣으면 보낼 수 있다', (tester) async {
    await pump(tester);

    await tester.tap(find.bySemanticsLabel('보내기'));
    await tester.pump();
    expect(repository.sent, isEmpty);

    await tester.enterText(find.byType(TextField), '안녕하세요');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('보내기'));
    await tester.pumpAndSettle();

    expect(repository.sent, ['안녕하세요']);
  });

  testWidgets('공백만 입력하면 보내지 않는다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('보내기'));
    await tester.pump();

    expect(repository.sent, isEmpty);
  });

  testWidgets('1,000자를 넘겨 쓸 수 없다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'ㄱ' * 1100);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, messageMaxLength);
  });

  testWidgets('나가기는 확인 다이얼로그를 거친다', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('채팅방 나가기'));
    await tester.pumpAndSettle();

    expect(find.text('채팅방을 나갈까요?'), findsOneWidget);
    // 되돌릴 수 없다는 것과 상대에게 보인다는 것을 둘 다 적는다(결정 7).
    expect(find.text('나가면 이 대화를 다시 볼 수 없고, 상대에게는 나갔다고 표시돼요.'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repository.leaveCount, 0);
  });

  testWidgets('통과한 방에는 신뢰 확인 카드와 카카오톡 아이디가 붙는다', (tester) async {
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

    await pump(tester);

    expect(find.byType(TrustRevealBubble), findsOneWidget);
    expect(find.text('fox_rain'), findsOneWidget);
    // 14c 는 뒤 조각이라 버튼을 그리지 않는다.
    expect(find.text('상대 프로필 보기'), findsNothing);
  });
}
