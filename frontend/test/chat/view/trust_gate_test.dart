import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/trust_banner.dart';
import 'package:campus_mate/chat/view/trust_gate_sheet.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_chat_repository.dart';

void main() {
  late FakeChatRepository repository;
  late FakeMessageStream stream;

  setUp(() {
    repository = FakeChatRepository();
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

  DateTime hoursAgo(int hours) => DateTime.now().subtract(Duration(hours: hours));

  testWidgets('24시간 전에는 시트가 아니라 미리 수락 배너가 뜬다', (tester) async {
    repository.room = Success(roomFixture(createdAt: hoursAgo(1)));

    await pump(tester);

    expect(find.byType(TrustGateSheet), findsNothing);
    expect(find.text('카카오톡 아이디를 먼저 공유해도 돼요'), findsOneWidget);
    expect(find.text('수락하기'), findsOneWidget);
  });

  testWidgets('배너 수락은 확인 다이얼로그를 거쳐야 서버로 간다', (tester) async {
    repository.room = Success(roomFixture(createdAt: hoursAgo(1)));
    await pump(tester);

    await tester.tap(find.text('수락하기'));
    await tester.pumpAndSettle();

    expect(find.text('카카오톡 아이디·실사진 공개를 수락할까요?'), findsOneWidget);
    expect(find.text('수락하면 채팅창에 수락했다는 문구가 상대에게 전송됩니다.'), findsOneWidget);
    expect(repository.trustCount, 0);

    repository.room = Success(roomFixture(createdAt: hoursAgo(1), myResponse: 'accept'));
    await tester.tap(find.text('수락').last);
    await tester.pumpAndSettle();

    expect(repository.trustCount, 1);
    expect(find.text('수락했어요. 상대의 응답을 기다리고 있어요'), findsOneWidget);
  });

  testWidgets('24시간이 지나고 미수락이면 시트가 뜬다', (tester) async {
    repository.room = Success(roomFixture(createdAt: hoursAgo(25)));

    await pump(tester);

    expect(find.byType(TrustGateSheet), findsOneWidget);
    expect(find.text('카카오톡 아이디를 공유할까요?'), findsOneWidget);
    // pen 라벨은 "거절하기" 였다 — 거절이 곧 나가기가 되면서 라벨이 그 사실을 말해야 한다(결정 11).
    expect(find.text('거절하고 나가기'), findsOneWidget);
  });

  testWidgets('시트를 닫으면 종료 예정 배너로 바뀐다', (tester) async {
    repository.room = Success(roomFixture(createdAt: hoursAgo(25)));
    await pump(tester);

    Navigator.of(tester.element(find.byType(TrustGateSheet))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(TrustGateSheet), findsNothing);
    expect(find.textContaining('이 대화는'), findsOneWidget);
    expect(find.text('응답 기한이 지나면 대화 목록에서 사라져요'), findsOneWidget);
  });

  testWidgets('거절하고 나가기는 나가기 다이얼로그를 거쳐 /leave 만 부른다', (tester) async {
    repository.room = Success(roomFixture(createdAt: hoursAgo(25)));
    await pump(tester);

    await tester.tap(find.text('거절하고 나가기'));
    await tester.pumpAndSettle();

    // 앱바 메뉴의 나가기와 같은 다이얼로그다 — 게이트 전용 거절 문구를 따로 만들지 않는다.
    expect(find.text('채팅방을 나갈까요?'), findsOneWidget);

    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();

    expect(repository.leaveCount, 1);
    // 거절 전용 호출은 존재하지 않는다(결정 11).
    expect(repository.trustCount, 0);
  });

  testWidgets('상대가 나간 방에서는 배너도 시트도 안 뜬다', (tester) async {
    repository.room = Success(roomFixture(createdAt: hoursAgo(25), partnerLeft: true));

    await pump(tester);

    expect(find.byType(TrustGateSheet), findsNothing);
    expect(find.byType(TrustBanner), findsNothing);
  });

  testWidgets('통과한 방에는 배너가 없다', (tester) async {
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

    await pump(tester);

    expect(find.byType(TrustBanner), findsNothing);
    expect(find.text('신뢰 확인 완료'), findsOneWidget);
  });
}
