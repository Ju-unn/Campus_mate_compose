import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 신고 · 차단 흐름 자체는 채팅방(chat_room_safety_test)과 14c(partner_profile_screen_test)가 확인한다.
void main() {
  testWidgets('완료 토스트는 공용 AppToast 로 pen yEDB9 크기(288×60, 글자 232×40)다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSafetyToast(ScaffoldMessenger.of(context), reportedMessage),
            child: const Text('띄우기'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('띄우기'));
    await tester.pumpAndSettle();

    final toast = find.byType(AppToast);
    expect(toast, findsOneWidget);
    expect(tester.getSize(toast), const Size(288, 60));
    expect(tester.getSize(find.text(reportedMessage)), const Size(232, 40));
    expect(find.descendant(of: toast, matching: find.byIcon(AppIcons.circleCheck)), findsOneWidget);
  });

  testWidgets('아이콘을 넘기면 그 아이콘으로 띄운다(실패 · 404 안내)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSafetyToast(ScaffoldMessenger.of(context), '프로필을 찾을 수 없어요', icon: AppIcons.circleAlert),
            child: const Text('띄우기'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('띄우기'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AppToast), matching: find.byIcon(AppIcons.circleAlert)), findsOneWidget);
    expect(find.byIcon(AppIcons.circleCheck), findsNothing);
  });
}
