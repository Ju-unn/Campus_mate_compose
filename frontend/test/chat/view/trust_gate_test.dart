import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/trust_banner.dart';
import 'package:campus_mate/chat/view/trust_gate_sheet.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_view_model.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Future<void> pump(WidgetTester tester, {DateTime Function()? now}) async {
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        messageStreamProvider.overrideWithValue(stream),
        if (now != null) chatRoomNowProvider.overrideWithValue(now),
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

  testWidgets('시트는 공유할 내 아이디를 보여주고 수락은 다이얼로그 없이 바로 간다', (tester) async {
    // pen `p0XJA6` 에는 확인 다이얼로그가 없다 — 아이디까지 보여 준 시트가 곧 확인이다.
    // 배너(14g)는 그대로 한 번 더 묻는다(위 테스트).
    repository.room = Success(roomFixture(createdAt: hoursAgo(25), myKakaoId: 'fox_rain_me'));
    await pump(tester);

    expect(find.text('공유할 카카오톡 아이디'), findsOneWidget);
    expect(find.text('fox_rain_me'), findsOneWidget);

    await tester.tap(find.text('수락하고 공유하기'));
    await tester.pumpAndSettle();

    expect(find.text('카카오톡 아이디·실사진 공개를 수락할까요?'), findsNothing);
    expect(repository.trustCount, 1);
  });

  testWidgets('내 아이디를 못 받았으면 빈 칸 대신 자리를 보여준다', (tester) async {
    // 서버 배포 전(응답에 my_kakao_id 가 없음)에도 시트가 무너지지 않아야 한다.
    repository.room = Success(roomFixture(createdAt: hoursAgo(25)));
    await pump(tester);

    expect(find.text('공유할 카카오톡 아이디'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
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

  testWidgets('방에 머무는 중 24시간 경계를 넘으면 그 자리에서 시트가 뜬다(백로그 22)', (tester) async {
    // 실제 시계에 기대지 않는다 — 화면 시계를 갈아끼우고 Timer 는 가짜 시간으로 넘긴다.
    var now = DateTime(2026, 9, 22, 12);
    final created = now.subtract(trustGateReminderAfter).add(const Duration(minutes: 1));
    repository.room = Success(roomFixture(createdAt: created));
    await pump(tester, now: () => now);

    expect(find.byType(TrustGateSheet), findsNothing);
    expect(find.text('카카오톡 아이디를 먼저 공유해도 돼요'), findsOneWidget);

    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(find.byType(TrustGateSheet), findsOneWidget);
    // 미리 수락 배너도 같이 내려간다 — 시트가 뜨는 단계에는 배너가 없다.
    expect(find.text('카카오톡 아이디를 먼저 공유해도 돼요'), findsNothing);
  });

  testWidgets('통과한 방에는 배너가 없다', (tester) async {
    repository.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));

    await pump(tester);

    expect(find.byType(TrustBanner), findsNothing);
    expect(find.text('신뢰 확인 완료'), findsOneWidget);
  });

  group('저장된 아이디 "변경"(pen p0XJA6 dB7yu · Ek58H → 16e-1)', () {
    Future<void> pumpSheet(WidgetTester tester, {VoidCallback? onChangeKakaoId}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TrustGateSheet(
            deadlineAt: DateTime.now().add(const Duration(hours: 20)),
            myKakaoId: 'fox_rain_me',
            onAccept: () {},
            onLeave: () {},
            onChangeKakaoId: onChangeKakaoId,
          ),
        ),
      ));
    }

    testWidgets('14f 변경 calls onChangeKakaoId', (tester) async {
      var changes = 0;
      await pumpSheet(tester, onChangeKakaoId: () => changes++);

      await tester.tap(find.text('변경'));
      await tester.pump();

      expect(changes, 1);
    });

    testWidgets('변경은 아이디 칸 오른쪽, 누르는 높이 48, 글자 14/600 primary-text', (tester) async {
      await pumpSheet(tester, onChangeKakaoId: () {});

      final button = find.ancestor(of: find.text('변경'), matching: find.byType(TextButton));
      expect(tester.getSize(button).height, 48);
      expect(tester.getCenter(button).dy, tester.getCenter(find.text('fox_rain_me')).dy);
      // 아이디 글자는 Expanded 라 오른쪽 끝이 곧 "변경"의 왼쪽 끝이다. 시트 좌우 16 안쪽, 칸 오른쪽 여백 4(pen d5T8Iu).
      expect(tester.getRect(button).left, greaterThanOrEqualTo(tester.getRect(find.text('fox_rain_me')).right));
      expect(tester.getRect(button).right, 800 - 16 - 4);
      // 칸 높이 56(pen d5T8Iu) — 배율 1.0 에서는 최소 높이가 곧 높이다.
      final box = find.ancestor(of: find.text('fox_rain_me'), matching: find.byType(Container)).first;
      expect(tester.getSize(box).height, 56);
      final style = tester.widget<Text>(find.text('변경')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.primaryText));
    });

    testWidgets('갈 곳을 받지 않으면 변경을 그리지 않는다', (tester) async {
      await pumpSheet(tester);

      expect(find.text('변경'), findsNothing);
    });

    // DESIGN §11.2 — "변경" 만큼 좁아진 칸에서 긴 아이디가 두 줄이 된다. 칸 높이를 56 에 묶으면 아래 줄이 표시 없이 잘린다.
    for (final scale in [1.3, 1.5]) {
      testWidgets('글자 배율 $scale 에서 "변경" 옆 긴 아이디가 잘리지 않는다', (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TrustGateSheet(
              deadlineAt: DateTime.now().add(const Duration(hours: 20)),
              myKakaoId: 'campus_fox_rain_2026',
              onAccept: () {},
              onLeave: () {},
              onChangeKakaoId: () {},
            ),
          ),
        ));

        final id = tester.renderObject<RenderParagraph>(find.text('campus_fox_rain_2026'));
        expect(id.getMaxIntrinsicHeight(id.size.width), lessThanOrEqualTo(id.size.height + 0.5));
      });
    }

    Future<void> pumpRoomInRouter(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repository),
          messageStreamProvider.overrideWithValue(stream),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '${AppRoutes.chatRoom}/m1',
        routes: [
          GoRoute(
            path: '${AppRoutes.chatRoom}/:matchId',
            builder: (context, state) => ChatRoomScreen(matchId: state.pathParameters['matchId']!),
          ),
          // 16e-1 자리. 저장 · 뒤로를 흉내 낸다.
          GoRoute(
            path: AppRoutes.kakaoIdSettings,
            builder: (context, state) => Scaffold(
              body: Column(children: [
                TextButton(onPressed: () => context.pop(true), child: const Text('저장한 척')),
                TextButton(onPressed: () => context.pop(), child: const Text('뒤로')),
              ]),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('chat room reloads after returning from 16e-1', (tester) async {
      repository.room = Success(roomFixture(createdAt: hoursAgo(25), myKakaoId: 'old_id'));
      await pumpRoomInRouter(tester);
      expect(find.text('old_id'), findsOneWidget);
      final fetchesBefore = repository.roomFetchCount;
      repository.room = Success(roomFixture(createdAt: hoursAgo(25), myKakaoId: 'new_id'));

      await tester.tap(find.text('변경'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장한 척'));
      await tester.pumpAndSettle();

      expect(repository.roomFetchCount, greaterThan(fetchesBefore));
      // 시트는 그대로 떠 있고 새로 읽은 아이디를 보여 준다 — 돌아와서 바로 수락할 수 있다.
      expect(find.byType(TrustGateSheet), findsOneWidget);
      expect(find.text('new_id'), findsOneWidget);
      expect(find.text('old_id'), findsNothing);
    });

    testWidgets('저장하지 않고 돌아오면 방을 다시 읽지 않는다', (tester) async {
      repository.room = Success(roomFixture(createdAt: hoursAgo(25), myKakaoId: 'old_id'));
      await pumpRoomInRouter(tester);
      final fetchesBefore = repository.roomFetchCount;

      await tester.tap(find.text('변경'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('뒤로'));
      await tester.pumpAndSettle();

      expect(repository.roomFetchCount, fetchesBefore);
      expect(find.text('old_id'), findsOneWidget);
    });
  });
}
