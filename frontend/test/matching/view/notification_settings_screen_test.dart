import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';
import 'package:campus_mate/matching/view/notification_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/push/fake_push_messaging.dart';
import '../model/fake_card_repository.dart';

void main() {
  late FakePushMessaging messaging;

  Future<FakeCardRepository> pump(WidgetTester tester, {bool permitted = true, Future<bool>? pending}) async {
    final repository = FakeCardRepository()
      ..preferences = const Success(NotificationPreferences());
    messaging = FakePushMessaging(token: 't')
      ..permitted = permitted
      ..permittedPending = pending;
    final container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        pushMessagingProvider.overrideWithValue(messaging),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();
    return repository;
  }

  testWidgets('서버가 가진 스위치를 그리고 댓글 스위치는 그리지 않는다', (tester) async {
    await pump(tester);

    expect(find.text('오늘의 카드 도착'), findsOneWidget);
    expect(find.text('받은 수락'), findsOneWidget);
    // 댓글 스위치는 대응 컬럼이 없어 이번 조각에서 그리지 않는다(커뮤니티는 조각 6).
    expect(find.text('내 글의 새 댓글'), findsNothing);
  });

  testWidgets('줄마다 pen 의 3D 그림이 그 순서로 그려진다(pen `wAQtn` · `zxXQG` · `U17hk` · `oq6tX` · `d7e1q` · `I58co`)', (tester) async {
    await pump(tester);

    final icons = [for (final icon in tester.widgetList<Icon3d>(find.byType(Icon3d, skipOffstage: false))) icon.icon];
    expect(icons, [
      AppIcon3d.layers, // 오늘의 카드 도착
      AppIcon3d.heart, // 받은 수락
      AppIcon3d.users, // 매칭 성립
      AppIcon3d.chat, // 새 메시지(pen 인스턴스 `K4uiNp` — 그림 확인 전)
      AppIcon3d.clock, // 신뢰 확인 리마인드
      AppIcon3d.heartHandshake, // 새 지인 리뷰(pen 인스턴스 `K4uiNp` — 그림 확인 전)
      AppIcon3d.megaphone, // 혜택·이벤트 소식
      AppIcon3d.moon, // 방해 금지 시간
    ]);
  });

  testWidgets('맨 아래에 조용한 시간 예외 안내가 있다', (tester) async {
    await pump(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pump();

    expect(find.text('방해 금지 시간 (22:00 ~ 08:00)'), findsOneWidget);
    expect(
      find.text('오늘의 카드 도착 알림은 방해 금지 시간에도 보내드려요. 카드가 도착하는 시각이 아침 7시예요.'),
      findsOneWidget,
    );
  });

  testWidgets('스위치 줄의 눌림 효과는 그 줄 안에서 그려진다', (tester) async {
    // 잉크는 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 목록을 밀어도 테두리가 제자리에 떠 있다(COMMON §4-2).
    await pump(tester);

    final tiles = find.byType(SwitchListTile);
    expect(tiles, findsWidgets);
    for (var i = 0; i < tiles.evaluate().length; i++) {
      final material = find.ancestor(of: tiles.at(i), matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(tiles.at(i)));
    }
  });

  testWidgets('스위치를 끄면 그 키만 서버로 간다', (tester) async {
    final repository = await pump(tester);

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump();

    expect(repository.preferenceUpdates.single, (key: 'card_arrived', value: false));
  });

  testWidgets('기기 알림이 켜져 있으면 기기 설정 안내가 없다', (tester) async {
    await pump(tester);

    expect(find.text('기기 알림 설정 열기'), findsNothing);
  });

  testWidgets('기기 알림이 꺼져 있으면 안내를 띄우고 누르면 기기 설정을 연다(16d-1)', (tester) async {
    // 앱 스위치가 다 켜져 있어도 기기에서 막으면 알림은 하나도 안 온다(A9).
    await pump(tester, permitted: false);

    await tester.tap(find.text('기기 알림 설정 열기'));
    await tester.pump();

    expect(messaging.openedSettings, 1);
  });

  testWidgets('기기 설정을 읽는 중에는 안내를 띄우지 않는다 — 켜진 사람에게 잠깐 떴다 사라지지 않게', (tester) async {
    await pump(tester, pending: Completer<bool>().future);

    expect(find.text('기기 알림 설정 열기'), findsNothing);
  });

  testWidgets('기기 설정에서 켜고 돌아오면 안내가 사라진다', (tester) async {
    await pump(tester, permitted: false);
    expect(find.text('기기 알림 설정 열기'), findsOneWidget);

    messaging.permitted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(find.text('기기 알림 설정 열기'), findsNothing);
  });
}
