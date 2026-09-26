import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/date_divider.dart';
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

  testWidgets('구독이 끊기면 배너가 뜨고 다시 시도로 메시지를 다시 읽는다', (tester) async {
    await pump(tester);
    final pagesBefore = repository.pages.length;

    stream.pushError();
    await tester.pumpAndSettle();
    expect(find.text('연결이 끊겼어요'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('연결이 끊겼어요'), findsNothing);
    expect(repository.pages.length, pagesBefore + 1);
  });

  testWidgets('통과한 방에는 신뢰 확인 카드와 카카오톡 아이디가 붙는다', (tester) async {
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

    await pump(tester);

    expect(find.byType(TrustRevealBubble), findsOneWidget);
    expect(find.text('fox_rain'), findsOneWidget);
    // 14c 는 뒤 조각이라 버튼을 그리지 않는다.
    expect(find.text('상대 프로필 보기'), findsNothing);
  });

  group('14b 카드 자리(백로그 20)', () {
    final passedAt = DateTime(2026, 9, 22, 12, 30);
    // 서버 /trust 는 요청 시작 시각으로 통과 도장을 찍고 **그 뒤에** 두 번째 수락 줄을 넣는다 —
    // 그래서 수락 줄이 통과 시각보다 몇 밀리초 늦다.
    List<Message> conversation() => [
          messageFixture(id: 'a', body: '안녕하세요', createdAt: DateTime(2026, 9, 22, 12)),
          messageFixture(
            id: 'b',
            kind: MessageKind.trustAccept,
            body: '여우비님이 카카오톡 아이디·실사진 공개를 수락했어요',
            createdAt: passedAt.add(const Duration(milliseconds: 40)),
          ),
          messageFixture(
            id: 'c',
            senderId: myId,
            body: '이제 카톡으로 얘기해요',
            createdAt: DateTime(2026, 9, 22, 12, 40),
          ),
        ];

    testWidgets('통과 뒤 대화보다 위, 마지막 수락 줄 바로 아래에 온다', (tester) async {
      repository.room = Success(roomFixture(passed: true, passedAt: passedAt, kakaoId: 'fox_rain'));
      repository.messages = Success(MessagePage(messages: conversation(), hasMore: false));

      await pump(tester);

      final card = tester.getTopLeft(find.byType(TrustRevealBubble)).dy;
      expect(card, greaterThan(tester.getTopLeft(find.textContaining('수락했어요')).dy));
      expect(card, lessThan(tester.getTopLeft(find.text('이제 카톡으로 얘기해요')).dy));
    });

    testWidgets('통과 시각을 모르면(서버 배포 전) 지금처럼 맨 아래에 둔다', (tester) async {
      repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
      repository.messages = Success(MessagePage(messages: conversation(), hasMore: false));

      await pump(tester);

      final card = tester.getTopLeft(find.byType(TrustRevealBubble)).dy;
      expect(card, greaterThan(tester.getTopLeft(find.text('이제 카톡으로 얘기해요')).dy));
    });

    testWidgets('다음 날 대화가 이어지면 카드는 그날 구분선 위에 남는다', (tester) async {
      repository.room = Success(roomFixture(passed: true, passedAt: passedAt, kakaoId: 'fox_rain'));
      repository.messages = Success(MessagePage(
        messages: [
          ...conversation().take(2),
          messageFixture(id: 'd', senderId: myId, body: '다음 날 인사', createdAt: DateTime(2026, 9, 23, 9)),
        ],
        hasMore: false,
      ));

      await pump(tester);

      final card = tester.getTopLeft(find.byType(TrustRevealBubble)).dy;
      final dividers = tester.widgetList<DateDivider>(find.byType(DateDivider)).toList();
      expect(dividers, hasLength(2));
      final nextDay = dividers.singleWhere((divider) => divider.date.day == 23);
      expect(card, lessThan(tester.getTopLeft(find.byWidget(nextDay)).dy));
      expect(card, greaterThan(tester.getTopLeft(find.textContaining('수락했어요')).dy));
    });
  });
}
