import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/chat/view/chat_intro_card.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/date_divider.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/chat/view/system_message.dart';
import 'package:campus_mate/chat/view/trust_banner.dart';
import 'package:campus_mate/chat/view/trust_reveal_bubble.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
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

  testWidgets('14g 나간 방(pen z5ULI): #F7F7F7 [16,16,28,16] → 안내 #FFF0F2 r12 14 · 14/400 body 1.5 → 12 → "채팅방 나가기" 52', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository.room = Success(roomFixture(partnerLeft: true));
    await pump(tester);

    const notice = '상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.';
    final noticeBox = find.ancestor(of: find.text(notice), matching: find.byType(DecoratedBox)).first;
    final boxDecoration = tester.widget<DecoratedBox>(noticeBox).decoration as BoxDecoration;
    expect((boxDecoration.color, boxDecoration.borderRadius), (AppColors.primaryWash, BorderRadius.circular(12)));
    final box = tester.getRect(noticeBox);
    expect(tester.getTopLeft(find.text(notice)) - box.topLeft, const Offset(14, 14));
    final style = tester.widget<Text>(find.text(notice)).style!;
    expect((style.fontSize, style.fontWeight, style.color, style.height), (14, FontWeight.w400, AppColors.body, 1.5));
    final button = tester.getRect(find.widgetWithText(AppButton, '채팅방 나가기'));
    expect((button.height, button.top - box.bottom, button.left, 360 - button.right), (52, 12, 16, 16));
    expect(box.left, 16);
    expect(780 - button.bottom, 28);
    final area = find.ancestor(of: noticeBox, matching: find.byType(ColoredBox)).first;
    expect(tester.widget<ColoredBox>(area).color, AppColors.surfaceSoft);
    expect(box.top - tester.getRect(area).top, 16);
  });

  testWidgets('14g "채팅방 나가기" → 확인 다이얼로그 → 나가면 저장소 leave', (tester) async {
    repository.room = Success(roomFixture(partnerLeft: true));
    await pump(tester);

    await tester.tap(find.widgetWithText(AppButton, '채팅방 나가기'));
    await tester.pumpAndSettle();
    expect(find.text('채팅방을 나갈까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '나가기'));
    await tester.pumpAndSettle();

    expect(repository.leaveCount, 1);
  });

  testWidgets('방을 보는 중에 상대가 나가면 그 자리에서 입력창이 안내로 바뀐다(E-CHAT-61)', (tester) async {
    await pump(tester);
    expect(find.byType(TextField), findsOneWidget);
    repository.room = Success(roomFixture(partnerLeft: true));

    stream.push(messageFixture(id: 'left-1', kind: MessageKind.left, body: '여우비님이 채팅방을 나갔어요'));
    await tester.pumpAndSettle();

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

  testWidgets('보내기에 성공하면 입력칸을 비운다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '안녕하세요');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('보내기'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('인터넷이 끊겨 못 보내면 쓴 글이 입력칸에 남아 다시 보낼 수 있다(결함 A4)', (tester) async {
    repository.sendResult = const FailureResult(NetworkFailure());
    await pump(tester);

    await tester.enterText(find.byType(TextField), '안녕하세요');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('보내기'));
    await tester.pumpAndSettle();

    expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '안녕하세요');

    repository.sendResult = const Success(null);
    await tester.tap(find.bySemanticsLabel('보내기'));
    await tester.pumpAndSettle();

    expect(repository.sent, ['안녕하세요', '안녕하세요']);
  });

  testWidgets('보내는 동안 새로 쓴 글은 실패해도 옛 글로 덮지 않는다', (tester) async {
    repository
      ..sendResult = const FailureResult(NetworkFailure())
      ..holdSend = Completer<void>();
    await pump(tester);

    await tester.enterText(find.byType(TextField), '안녕하세요');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('보내기'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '새 글');
    repository.holdSend!.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '새 글');
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

  group('글자 수는 서버·DB 처럼 코드포인트로 센다(백로그 21)', () {
    // 👨‍👩‍👧 는 보이는 글자 1개(grapheme)지만 코드포인트 5개다. 서버 len()·DB char_length 는 5 로 센다.
    const family = '👨‍👩‍👧';

    testWidgets('합성 이모지를 섞어 넘기면 앞 1,000 코드포인트로 자른다', (tester) async {
      await pump(tester);
      final input = '${'ㄱ' * 990}$family$family$family';
      expect(input.runes.length, 1005);
      expect(input.characters.length, 993);

      await tester.enterText(find.byType(TextField), input);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      final text = field.controller!.text;
      expect(text.runes.length, messageMaxLength);
      expect(text, String.fromCharCodes(input.runes.take(messageMaxLength)));
      // 잘린 뒤 커서는 끝에 둔다.
      expect(field.controller!.selection, TextSelection.collapsed(offset: text.length));
      // 한도는 formatter 하나로만 건다 — maxLength 를 같이 두면 grapheme 기준 한도가 겹친다.
      expect(field.maxLength, isNull);
    });

    testWidgets('한글 1,000자는 그대로 들어간다', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '가' * messageMaxLength);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '가' * messageMaxLength);
    });

    testWidgets('가득 찬 글 중간에 입력하면 글도 커서도 그대로다', (tester) async {
      // 끝 글자를 밀어내고 커서를 끝으로 보내면 쓰던 자리를 잃는다 — 옛 LengthLimiting 과 같게 막는다.
      await pump(tester);
      final full = '가' * messageMaxLength;
      await tester.enterText(find.byType(TextField), full);
      await tester.pump();
      final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
      controller.selection = const TextSelection.collapsed(offset: 500);
      await tester.pump();

      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: '${'가' * 500}ㄴ${'가' * 500}',
        selection: const TextSelection.collapsed(offset: 501),
      ));
      await tester.pump();

      expect(controller.text, full);
      expect(controller.selection, const TextSelection.collapsed(offset: 500));
    });

    testWidgets('긴 글을 앞에 붙여 넣으면 넘친 만큼 자르고 커서는 붙여 넣은 자리에 둔다', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '가' * 10);
      await tester.pump();

      // 맨 앞에 995자를 붙여 넣었다 — 커서는 붙여 넣은 끝(995)에 남고 글 끝으로 튀지 않는다.
      final pasted = '${'ㄴ' * 995}${'가' * 10}';
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: pasted,
        selection: const TextSelection.collapsed(offset: 995),
      ));
      await tester.pump();

      final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(controller.text, pasted.substring(0, messageMaxLength));
      expect(controller.selection, const TextSelection.collapsed(offset: 995));
    });
  });

  testWidgets('나가기는 확인 다이얼로그를 거친다', (tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(AppIcons.ellipsis));
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
    // 14c 로 가는 버튼(pen `vmfRQ`)이 카드 아래에 붙는다.
    expect(find.text('상대 프로필 보기'), findsOneWidget);
  });

  // 서버는 상대가 나갔거나 나를 차단했으면 카톡 아이디 · 실사진을 내리지 않는다(나를 차단한 방도 앱에는 "나간 방").
  // 카드를 그대로 두면 "아직 아이디를 등록하지 않았어요" 로 잘못 읽힌다 — 카드를 통째로 숨긴다(사용자 결정 09-27).
  testWidgets('통과했어도 상대가 나간 방에는 14b 카드가 없다', (tester) async {
    repository.room = Success(roomFixture(passed: true, partnerLeft: true));

    await pump(tester);

    expect(find.byType(TrustRevealBubble), findsNothing);
    expect(find.text('상대가 아직 아이디를 등록하지 않았어요'), findsNothing);
    expect(find.text('상대 프로필 보기'), findsNothing);
  });

  testWidgets('방에 있는 동안 상대가 나가 방을 다시 읽으면 14b 카드가 사라진다', (tester) async {
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
    await pump(tester);
    expect(find.byType(TrustRevealBubble), findsOneWidget);

    // 머리말은 들어올 때 · 다시 연결할 때 새로 읽는다 — 끊겼다 다시 붙는 길로 새 머리말을 받는다.
    repository.room = Success(roomFixture(passed: true, partnerLeft: true));
    stream.pushError();
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.byType(TrustRevealBubble), findsNothing);
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

  // 카톡식 안 읽음 '1'(사용자 결정 10-13, pen 구역 c57Ze). 내 text 말풍선마다 따로 붙는다.
  group('안 읽음 1(pen c57Ze)', () {
    final at = DateTime(2026, 10, 13, 14, 15);
    const lines = ['네 좋아요, 토요일 오후 어떠세요?', '3시쯤 학교 앞 카페 어때요?', '제가 자리 먼저 알아볼게요 :)'];

    /// 시안 Kq8Vr · MNWTN · hDNbq 의 아래쪽: 상대 한 줄(14:14) 뒤 같은 분(14:15)에 보낸 내 줄 3개.
    List<Message> sameMinuteRun() => [
          messageFixture(id: 'their', senderId: partnerId, body: '저도요! 혹시 이번 주말에 시간 괜찮으실까요?', createdAt: at.subtract(const Duration(minutes: 1))),
          for (var i = 0; i < lines.length; i++)
            messageFixture(id: 'mine-$i', senderId: myId, body: lines[i], createdAt: at.add(Duration(seconds: i * 10))),
        ];

    Future<void> pumpRead(WidgetTester tester, PartnerRead read, {List<Message>? messages, bool partnerLeft = false}) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repository.room = Success(roomFixture(partnerRead: read, partnerLeft: partnerLeft));
      repository.messages = Success(MessagePage(messages: messages ?? sameMinuteRun(), hasMore: false, partnerRead: read));
      await pump(tester);
    }

    Finder bubbleOf(String body) => find.widgetWithText(MessageBubble, body);
    Finder unreadMarks() => find.text('1');

    testWidgets('hDNbq 같은 분 3개를 모두 안 읽었으면 말풍선마다 1, 시각은 마지막에만, 사이 4', (tester) async {
      await pumpRead(tester, const PartnerRead.known(null));

      expect(unreadMarks(), findsNWidgets(3));
      for (final body in lines) {
        expect(find.descendant(of: bubbleOf(body), matching: unreadMarks()), findsOneWidget, reason: body);
      }
      expect(find.text('오후 2:15'), findsOneWidget);
      expect(find.descendant(of: bubbleOf(lines.last), matching: find.text('오후 2:15')), findsOneWidget);
      final rects = [for (final body in lines) tester.getRect(bubbleOf(body))];
      expect([rects[1].top - rects[0].bottom, rects[2].top - rects[1].bottom], [4, 4]);
    });

    testWidgets('Kq8Vr 앞 2개는 읽고 마지막 1개만 안 읽었으면 마지막에만 1', (tester) async {
      await pumpRead(tester, PartnerRead.known(at.add(const Duration(seconds: 15))));

      expect(unreadMarks(), findsOneWidget);
      expect(find.descendant(of: bubbleOf(lines.last), matching: unreadMarks()), findsOneWidget);
    });

    testWidgets('MNWTN 모두 읽었으면 1 이 하나도 없다', (tester) async {
      await pumpRead(tester, PartnerRead.known(at.add(const Duration(minutes: 1))));

      expect(unreadMarks(), findsNothing);
    });

    testWidgets('상대 말풍선과 시스템 줄에는 없다', (tester) async {
      await pumpRead(tester, const PartnerRead.known(null), messages: [
        messageFixture(id: 'their', senderId: partnerId, body: '안녕하세요', createdAt: at),
        messageFixture(id: 'sys', senderId: myId, kind: MessageKind.trustAccept, body: '카카오톡 아이디 공개를 수락했어요', createdAt: at),
      ]);

      expect(find.byType(SystemMessage), findsOneWidget);
      expect(unreadMarks(), findsNothing);
    });

    testWidgets('상대가 나간 방에서는 숨긴다 — 읽을 사람이 없다', (tester) async {
      await pumpRead(tester, const PartnerRead.known(null), partnerLeft: true);

      expect(unreadMarks(), findsNothing);
    });

    testWidgets('서버가 읽음 시각을 안 주면(옛 서버) 그리지 않는다', (tester) async {
      await pumpRead(tester, const PartnerRead.unknown());

      expect(unreadMarks(), findsNothing);
    });

    testWidgets('보내는 중이거나 보내기에 실패한 글에는 1 이 없다 — 말풍선이 생기지 않는다', (tester) async {
      await pumpRead(tester, const PartnerRead.known(null), messages: const []);
      repository.holdSend = Completer<void>();
      repository.sendResult = const FailureResult(NetworkFailure());

      await tester.enterText(find.byType(TextField), '보내는 중');
      await tester.tap(find.bySemanticsLabel('보내기'));
      await tester.pump();
      expect(unreadMarks(), findsNothing);

      repository.holdSend!.complete();
      await tester.pumpAndSettle();
      expect(unreadMarks(), findsNothing);
    });

    testWidgets('2초 확인에서 상대가 읽었으면 1 이 바로 사라진다(애니메이션 없음)', (tester) async {
      await pumpRead(tester, const PartnerRead.known(null));
      expect(unreadMarks(), findsNWidgets(3));

      repository.partnerReadResult = Success(PartnerRead.known(at.add(const Duration(minutes: 1))));
      await tester.pump(partnerReadPollFast);
      await tester.pump();

      expect(unreadMarks(), findsNothing);
    });

    testWidgets('앱이 백그라운드에 있는 동안은 묻지 않고, 돌아오면 바로 묻는다', (tester) async {
      await pumpRead(tester, const PartnerRead.known(null));
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }

      await tester.pump(const Duration(seconds: 20));
      expect(repository.partnerReadFetchCount, 0);

      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(repository.partnerReadFetchCount, greaterThanOrEqualTo(1));
    });

    // iOS 순서: 알림 센터 · 제어 센터를 내렸다 올리면 hidden 없이 inactive ↔ resumed 만 오간다 — 방은 계속 보이는 것이다.
    testWidgets('inactive ↔ resumed 만 오가면 확인이 끊기지 않는다', (tester) async {
      await pumpRead(tester, const PartnerRead.known(null));
      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump(const Duration(milliseconds: 500));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
      }
      final before = repository.partnerReadFetchCount;

      await tester.pump(partnerReadPollFast);
      expect(repository.partnerReadFetchCount, greaterThan(before));
    });

    testWidgets('다른 화면이 방을 덮으면 멈추고, 돌아오면 바로 묻는다', (tester) async {
      await pumpRead(tester, const PartnerRead.known(null));
      unawaited(Navigator.of(tester.element(find.byType(ChatRoomScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('상대 프로필')))));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 20));
      expect(repository.partnerReadFetchCount, 0);

      Navigator.of(tester.element(find.text('상대 프로필'))).pop();
      await tester.pumpAndSettle();
      expect(repository.partnerReadFetchCount, 1);
    });
  });

  // 매칭 직후 첫 입장 안내 카드(pen 화면 PI7Kg 접힘 · U6x9nV 펼침, 마스터 cinKv · TfPlG). DB · 서버 변경 없이
  // 앱이 메시지 목록 맨 위에 끼운다. 24시간 전 · 내가 수락 전(preAccept) · 공개 전 · 상대 있음 · 기한 전일 때만 보인다
  // (대장 결정 10-17, 규칙 자체는 chat_room_ui_state_test). 카드가 보이는 방은 목록을 위로 붙인다(대장 결정 B) —
  // 목록 안쪽 사방 16 · 카드 아래 간격 14 · 빈 방 문구 16/400 1.6 muted 가운데 폭 = 카드(pen PI7Kg · U6x9nV).
  group('첫 입장 안내 카드', () {
    const hint = '먼저 인사를 건네 보세요';
    final introItem = "지금부터 48시간이 '신뢰 확인' 시간이에요. 서로 카카오톡 아이디와 실제 사진을 공개해도 좋은지 정하는 시간이에요.";

    Future<void> pumpRoom(
      WidgetTester tester, {
      List<Message> messages = const [],
      bool hasMore = false,
      double scale = 1,
      double height = 780,
    }) async {
      tester.view.physicalSize = Size(360, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      repository.messages = Success(MessagePage(messages: messages, hasMore: hasMore));
      await pump(tester);
    }

    List<Message> conversation(int count) => [
          for (var index = 0; index < count; index++)
            messageFixture(
              id: 'm$index',
              senderId: index.isEven ? partnerId : myId,
              body: '메시지 $index',
              createdAt: DateTime(2026, 10, 17, 9).add(Duration(minutes: index)),
            ),
        ];

    testWidgets('빈 방 — 카드는 목록 안 배너 아래, 폭 328 · 왼쪽 16, 접힌 채로 시작한다', (tester) async {
      await pumpRoom(tester);

      expect(find.byType(ChatIntroCard), findsOneWidget);
      expect(find.ancestor(of: find.byType(ChatIntroCard), matching: find.byType(ListView)), findsOneWidget);
      final card = tester.getRect(find.byType(ChatIntroCard));
      expect((card.width, card.left), (328, 16));
      // 위 정렬(대장 결정 B): 배너 아래 끝 → 카드 위 끝 16(pen PI7Kg 목록 안쪽 16).
      expect(card.top - tester.getRect(find.byType(TrustBanner)).bottom, 16);
      expect(tester.widget<ChatIntroCard>(find.byType(ChatIntroCard)).expanded, isFalse);
      expect(find.text('자세히 보기'), findsOneWidget);
    });

    testWidgets('빈 방 문구는 카드 아래, 입력창 위에 겹치지 않게 놓인다', (tester) async {
      await pumpRoom(tester);

      final card = tester.getRect(find.byType(ChatIntroCard));
      final text = tester.getRect(find.text(hint));
      // pen PI7Kg: 카드 → 문구 14, 문구 폭 = 카드 폭 · 가운데 정렬 · 16/400 1.6 muted.
      expect(text.top - card.bottom, 14);
      expect((text.left, text.width), (card.left, card.width));
      final textWidget = tester.widget<Text>(find.text(hint));
      final style = textWidget.style!;
      expect((style.fontSize, style.fontWeight, style.height, style.color), (16, FontWeight.w400, 1.6, AppColors.muted));
      expect(textWidget.textAlign, TextAlign.center);
      expect(text.bottom, lessThanOrEqualTo(tester.getRect(find.byType(ChatInputBar)).top));
    });

    testWidgets('메시지가 있으면 빈 방 문구가 없고, 카드는 첫 줄(날짜 구분선)보다 위다', (tester) async {
      await pumpRoom(tester, messages: conversation(2));

      expect(find.text(hint), findsNothing);
      final card = tester.getRect(find.byType(ChatIntroCard));
      // 짧은 대화도 위로 붙는다 — 배너 아래 16, 카드 → 첫 줄(날짜 구분선) 14.
      expect(card.top - tester.getRect(find.byType(TrustBanner)).bottom, 16);
      expect(tester.getRect(find.byType(DateDivider)).top - card.bottom, 14);
      expect(card.bottom, lessThanOrEqualTo(tester.getRect(find.text('메시지 0')).top));
    });

    testWidgets('첫 메시지가 오면 빈 방 문구가 사라지고 카드는 남는다', (tester) async {
      await pumpRoom(tester);

      stream.push(messageFixture(id: 'first', body: '안녕하세요'));
      await tester.pumpAndSettle();

      expect(find.text(hint), findsNothing);
      expect(find.byType(ChatIntroCard), findsOneWidget);
    });

    testWidgets('통과(공개)한 방에는 카드가 없다', (tester) async {
      repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
      await pumpRoom(tester, messages: conversation(2));

      expect(find.byType(ChatIntroCard), findsNothing);
    });

    testWidgets('내가 먼저 수락한 방(14g)에는 카드가 없고, 빈 방 문구는 예전처럼 목록 자리 가운데다', (tester) async {
      repository.room = Success(roomFixture(myResponse: 'accept'));
      await pumpRoom(tester);

      expect(find.byType(ChatIntroCard), findsNothing);
      // 목록 자리 = 14g 배너 아래 끝 ~ 입력창 위 끝.
      final top = tester.getRect(find.byType(TrustBanner)).bottom;
      final bottom = tester.getRect(find.byType(ChatInputBar)).top;
      expect(tester.getCenter(find.text(hint)).dy, moreOrLessEquals((top + bottom) / 2, epsilon: 1));
    });

    testWidgets('매칭 24시간이 지난 방(14f 시트 · 14h)에는 카드가 없다', (tester) async {
      repository.room = Success(roomFixture(createdAt: DateTime.now().subtract(const Duration(hours: 25))));
      await pumpRoom(tester, messages: conversation(2));

      expect(find.byType(ChatIntroCard), findsNothing);
    });

    testWidgets('상대가 나간 방에는 카드가 없다', (tester) async {
      repository.room = Success(roomFixture(partnerLeft: true));
      await pumpRoom(tester);

      expect(find.byType(ChatIntroCard), findsNothing);
    });

    testWidgets('방에 있는 동안 공개되면(방을 다시 읽음) 카드가 사라진다', (tester) async {
      await pumpRoom(tester);
      expect(find.byType(ChatIntroCard), findsOneWidget);

      repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
      stream.pushError();
      await tester.pumpAndSettle();
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatIntroCard), findsNothing);
    });

    testWidgets('맨 앞 줄을 아직 안 읽었으면(이전 페이지가 남음) 카드를 그리지 않는다 — 첫 메시지보다 위가 아니다', (tester) async {
      await pumpRoom(tester, messages: conversation(3), hasMore: true);

      expect(find.byType(ChatIntroCard), findsNothing);
    });

    testWidgets('"자세히 보기" → 5항목 펼침 → 새 메시지가 와도 펼친 채 → "접기" → 접힘', (tester) async {
      await pumpRoom(tester);

      await tester.tap(find.text('자세히 보기'));
      await tester.pumpAndSettle();
      expect(find.text(introItem), findsOneWidget);
      expect(find.text('5.'), findsOneWidget);

      // 접힘 상태는 화면 상태에 둔다 — 목록이 다시 그려져도(새 줄) 펼친 채다.
      stream.push(messageFixture(id: 'first', body: '안녕하세요'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChatIntroCard>(find.byType(ChatIntroCard)).expanded, isTrue);

      await tester.tap(find.text('접기'));
      await tester.pumpAndSettle();
      expect(find.text(introItem), findsNothing);
      expect(find.text('자세히 보기'), findsOneWidget);
    });

    testWidgets('짧은 방에서 펼치면 카드 위 끝(제목)이 제자리이고 아래로 늘어난다', (tester) async {
      // 펼친 카드가 다 들어가는 키 큰 화면. 넘치는 화면은 그대로 스크롤로 본다(대장 결정 — C 는 넣지 않음).
      await pumpRoom(tester, height: 1100);
      final card = tester.getRect(find.byType(ChatIntroCard));

      await tester.tap(find.text('자세히 보기'));
      await tester.pumpAndSettle();

      final expanded = tester.getRect(find.byType(ChatIntroCard));
      expect(expanded.top, card.top);
      expect(expanded.bottom, greaterThan(card.bottom));
      expect(tester.getRect(find.text(hint)).top - expanded.bottom, 14);
    });

    testWidgets('긴 방에서 펼쳐도 스크롤 위치가 튀지 않는다 — 누른 토글이 손가락 아래에 그대로 있다', (tester) async {
      await pumpRoom(tester, messages: conversation(40));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('자세히 보기'), 300, scrollable: list);
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(list);
      final pixels = scrollable.position.pixels;
      final before = tester.getRect(find.widgetWithText(TextButton, '자세히 보기'));
      final oldest = tester.getRect(find.text('메시지 0')).top;

      await tester.tap(find.text('자세히 보기'));
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, pixels);
      expect(tester.getRect(find.widgetWithText(TextButton, '접기')).top, before.top);
      expect(tester.getRect(find.text('메시지 0')).top, oldest);
    });

    testWidgets('펼친 카드가 화면을 넘으면 스크롤로 다 볼 수 있다(제목 · 접기)', (tester) async {
      await pumpRoom(tester);
      final list = find.byType(Scrollable).first;

      await tester.tap(find.text('자세히 보기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('접기').hitTestable(), findsOneWidget);

      await tester.scrollUntilVisible(find.text('대화를 시작하기 전에 알아 두세요'), 100, scrollable: list);
      // scrollUntilVisible 은 마지막에 ensureVisible 로 옮기기만 하고 프레임을 그리지 않는다.
      await tester.pumpAndSettle();
      expect(find.text('대화를 시작하기 전에 알아 두세요').hitTestable(), findsOneWidget);
    });

    testWidgets('메시지가 쌓이면 카드는 목록 맨 위에서 메시지와 함께 스크롤된다', (tester) async {
      await pumpRoom(tester, messages: conversation(40));
      final list = find.byType(Scrollable).first;

      // 아래(최신)가 먼저 보인다 — 카드는 화면 밖 맨 위다.
      expect(find.byType(ChatIntroCard).hitTestable(), findsNothing);
      await tester.scrollUntilVisible(find.byType(ChatIntroCard), 300, scrollable: list);
      await tester.pumpAndSettle();

      final card = tester.getRect(find.byType(ChatIntroCard));
      expect(card.bottom, lessThanOrEqualTo(tester.getRect(find.text('메시지 0')).top));
      final oldest = tester.getRect(find.text('메시지 0')).top;
      await tester.drag(list, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ChatIntroCard)).top - card.top, tester.getRect(find.text('메시지 0')).top - oldest);
      expect(tester.getRect(find.byType(ChatIntroCard)).top, lessThan(card.top));
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale — 빈 방 접힘 · 펼침 모두 넘치지 않는다', (tester) async {
        await pumpRoom(tester, scale: scale);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('자세히 보기'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('접기'), findsOneWidget);
      });
    }
  });
}
