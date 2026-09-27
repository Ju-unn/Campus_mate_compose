import 'package:campus_mate/chat/view/chat_room_menu_sheet.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatRoomMenuAction? picked;
  late bool closed;

  setUp(() {
    picked = null;
    closed = false;
  });

  Future<void> open(WidgetTester tester, {double scale = 1, bool canTargetPartner = true}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showChatRoomMenuSheet(context, canTargetPartner: canTargetPartner);
                closed = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('행은 신고하기 · 차단하기 · 채팅방 나가기 순서다(pen hUrVg)', (tester) async {
    await open(tester);

    final report = tester.getTopLeft(find.text('신고하기')).dy;
    final block = tester.getTopLeft(find.text('차단하기')).dy;
    final leave = tester.getTopLeft(find.text('채팅방 나가기')).dy;
    final cancel = tester.getTopLeft(find.text('취소')).dy;
    expect(report < block && block < leave && leave < cancel, isTrue);
    // 행 간격 4 + 행 52 = 56(pen WAKrs y20 → qXoWf y76).
    expect(block - report, 56);
  });

  testWidgets('차단하기만 아이콘과 글자가 빨강(error)이다', (tester) async {
    await open(tester);

    expect(tester.widget<Text>(find.text('차단하기')).style!.color, AppColors.error);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.userX)).color, AppColors.error);
    expect(tester.widget<Text>(find.text('신고하기')).style!.color, AppColors.ink);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.flag)).color, AppColors.ink);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.logOut)).color, AppColors.ink);
  });

  testWidgets('pen 크기 — 시트 360×269, 행 328×52', (tester) async {
    await open(tester);

    expect(tester.getSize(find.byType(ChatRoomMenuSheet)), const Size(360, 269));
    for (final label in ['신고하기', '차단하기', '채팅방 나가기', '취소']) {
      final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      expect(tester.getSize(ink), const Size(328, 52), reason: label);
      // 눌림 효과는 행 안의 Material 에 그린다(COMMON §4-2).
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), const Size(328, 52), reason: label);
    }
  });

  testWidgets('상대를 모르면 채팅방 나가기 · 취소 두 줄만 있고, 잉크는 줄 안 Material 에 그린다', (tester) async {
    await open(tester, canTargetPartner: false);

    expect(find.text('신고하기'), findsNothing);
    expect(find.text('차단하기'), findsNothing);
    expect(
      find.descendant(of: find.byType(ChatRoomMenuSheet), matching: find.byType(InkWell)),
      findsNWidgets(2),
    );
    for (final label in ['채팅방 나가기', '취소']) {
      final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      expect(tester.getSize(ink), const Size(328, 52), reason: label);
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), const Size(328, 52), reason: label);
    }

    await tester.tap(find.text('채팅방 나가기'));
    await tester.pumpAndSettle();
    expect(picked, ChatRoomMenuAction.leave);
  });

  testWidgets('고른 행을 돌려주고, 취소는 null', (tester) async {
    await open(tester);
    await tester.tap(find.text('차단하기'));
    await tester.pumpAndSettle();
    expect(picked, ChatRoomMenuAction.block);

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    closed = false;
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(picked, isNull);
  });

  testWidgets('글자 2배에서도 넘치지 않는다', (tester) async {
    await open(tester, scale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('취소').hitTestable(), findsOneWidget);
  });
}
