import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
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
    expect(find.text('받은 신청'), findsOneWidget);
    expect(find.text('상대가 나에게 대화를 신청했을 때'), findsOneWidget);
    // 매칭 성사 알림 행은 사용자 확인 전까지 옛 글자 그대로다(지시문 23 F).
    expect(find.text('서로 수락해 대화가 열렸을 때'), findsOneWidget);
    // 댓글 스위치는 대응 컬럼이 없어 이번 조각에서 그리지 않는다(커뮤니티는 조각 6).
    expect(find.text('내 글의 새 댓글'), findsNothing);
  });

  testWidgets('줄마다 pen 의 3D 그림이 그 순서로 그려진다(pen `wAQtn` · `zxXQG` · `U17hk` · `oq6tX` · `d7e1q` · `I58co`)', (tester) async {
    await pump(tester);

    final icons = [for (final icon in tester.widgetList<Icon3d>(find.byType(Icon3d, skipOffstage: false))) icon.icon];
    expect(icons, [
      AppIcon3d.layers, // 오늘의 카드 도착
      AppIcon3d.heart, // 받은 신청
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

  testWidgets('줄 안쪽: 아이콘 22 · 글 사이 12 · 라벨 16/normal #222222 · 설명 12/normal #6A6A6A · 스위치 색(pen `jtLpv` · `b6Be6` · `cjlyY`)', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);

    for (final icon in tester.widgetList<Icon3d>(find.byType(Icon3d))) {
      expect(icon.size, 22);
    }
    final title = tester.widget<Text>(find.text('오늘의 카드 도착')).style!;
    expect((title.fontSize, title.fontWeight, title.color), (16.0, FontWeight.w400, const Color(0xFF222222)));
    final note = tester.widget<Text>(find.text('매일 아침 7시 지급 알림')).style!;
    expect((note.fontSize, note.fontWeight, note.color, note.height), (12.0, FontWeight.w400, const Color(0xFF6A6A6A), 1.4));
    // 아이콘 오른쪽 끝 → 글 왼쪽 = 12
    final icon = tester.getRect(find.byType(Icon3d).first);
    expect(tester.getRect(find.text('오늘의 카드 도착')).left - icon.right, 12);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile).first);
    expect(tile.activeTrackColor, const Color(0xFFFF385C));
    expect(tile.inactiveTrackColor, const Color(0xFFDDDDDD));
    expect(tile.activeThumbColor, const Color(0xFFFFFFFF));
  });

  testWidgets('줄 높이 · 아래 선: 부연 있는 64 줄은 모두 선이 있고, 52 줄은 카드의 마지막 줄만 선이 없다', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);

    bool hasLine(String title) {
      final box = find.ancestor(of: find.text(title), matching: find.byType(Container)).evaluate().map((e) => e.widget as Container).firstWhere((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).border != null || c.constraints != null && c.constraints!.minHeight > 0);
      return (box.decoration as BoxDecoration?)?.border != null;
    }

    expect(hasLine('오늘의 카드 도착'), isTrue); // 64
    expect(hasLine('매칭 성립'), isTrue); // 64 · 카드의 마지막 줄이어도 선 있음
    expect(hasLine('새 메시지'), isTrue); // 52 · 카드 첫 줄
    expect(hasLine('새 지인 리뷰'), isFalse); // 52 · 카드의 마지막(유일한) 줄
    expect(hasLine('방해 금지 시간 (22:00 ~ 08:00)'), isFalse); // 52 · 카드의 마지막 줄
  });

  group('카드 묶음 틀(pen `Znioc` · `kX4oK` · `LvHyT` · `URYwe` · `YAt0F`)', () {
    // pen 폭 360 화면 — 카드 328(좌우 16). 높이는 pen 의 머리 28 + 줄(부연 있음 64 · 없음 52).
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Finder card(String firstRow) => find.ancestor(
          of: find.text(firstRow),
          matching: find.byWidgetPredicate((w) => w is Material && w.shape is RoundedRectangleBorder && w.color == AppColors.surfaceSoft),
        );

    testWidgets('섹션 카드 넷: 폭 328 · 높이 = 줄 합(+테두리), #F7F7F7 · 테두리 #DDDDDD · 모서리 12', (tester) async {
      phone(tester);
      await pump(tester);

      // 매칭 3줄 64×3 · 대화 52 + 64 · 지인 리뷰 52(앱에는 한 줄 — "내 글의 새 댓글" 보류) · 기타 64 + 52.
      // pen 높이는 최소값이다 — 시험 글꼴(Ahem)은 한글이 넓어 부연 글이 두 줄로 꺾이면 줄이 더 커진다. 부연 글 없는 지인 리뷰 줄만 딱 맞는다.
      final heights = {'오늘의 카드 도착': 192.0, '새 메시지': 116.0, '새 지인 리뷰': 52.0, '혜택·이벤트 소식': 116.0};
      for (final MapEntry(key: first, value: height) in heights.entries) {
        final found = card(first);
        expect(found, findsOneWidget, reason: first);
        expect(tester.getSize(found).width, 328, reason: first);
        expect(tester.getSize(found).height, greaterThanOrEqualTo(height), reason: first);
        if (first == '새 지인 리뷰') expect(tester.getSize(found).height, height, reason: first); // 줄 아래 선은 줄 높이 안에 든다
        final material = tester.widget<Material>(found);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(12));
        expect(shape.side.color, AppColors.hairline);
      }
    });

    testWidgets('머리 14/700 #6A6A6A 줄 높이 20 · 머리와 카드 사이 8 · 카드 사이 20 · 목록 위 12', (tester) async {
      phone(tester);
      await pump(tester);

      final header = tester.widget<Text>(find.text('매칭'));
      expect(header.style!.fontSize, 14);
      expect(header.style!.fontWeight, FontWeight.w700);
      expect(header.style!.color, AppColors.muted);
      expect(tester.getTopLeft(find.text('매칭')).dy, 56 + 12); // 앱바 56 아래 목록 위 여백 12
      expect(tester.getSize(find.text('매칭')).height, 20);
      final first = tester.getRect(card('오늘의 카드 도착'));
      expect(first.top, 56 + 12 + 20 + 8);
      final second = tester.getRect(card('새 메시지'));
      expect(second.top - first.bottom, 20 + 20 + 8); // 카드 → 20 → 다음 머리(20) → 8 → 카드
      expect(first.left, 16);
    });

    testWidgets('기기 알림이 꺼진 상태(16d-1): 안내 상자 → 20 → 버튼 → 20 → 첫 머리, 목록 위 12', (tester) async {
      phone(tester);
      await pump(tester, permitted: false);

      final notice = find.ancestor(
        of: find.textContaining('기기 알림이 꺼져 있어요'),
        matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.primaryWash),
      );
      final box = tester.getRect(notice);
      expect(box.top, 56 + 12);
      expect(box.width, 328);
      final button = tester.getRect(find.widgetWithText(AppButton, '기기 알림 설정 열기'));
      expect(button.top - box.bottom, 20);
      expect(button.width, 328);
      expect(tester.getTopLeft(find.text('매칭')).dy - button.bottom, 20);
    });

    testWidgets('"내 글의 새 댓글" 은 대응 컬럼이 없어 그리지 않는다(보류 — 사용자 결정 필요)', (tester) async {
      await pump(tester);

      expect(find.text('내 글의 새 댓글'), findsNothing);
    });
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
