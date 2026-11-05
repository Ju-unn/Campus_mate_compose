import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/safety/model/repository/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/model/repository/fake_chat_repository.dart';
import '../model/repository/fake_safety_repository.dart';

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
            onPressed: () => showSafetyToast(ScaffoldMessenger.of(context), AppLocalizationsKo().safetyReported),
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
    expect(tester.getSize(find.text(AppLocalizationsKo().safetyReported)), const Size(232, 40));
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

  // blockThenLeave 는 글자가 아니라 Failure 를 돌려준다 — 보여 주는 자리는 화면마다 다르고 글자는 그 화면이 context.errorText 로 만든다.
  group('blockThenLeave', () {
    Object? returned;

    /// "열기" → 14e 확인 시트 → [tapLabel] 을 누른 뒤까지 간다.
    Future<void> openAndTap(WidgetTester tester, FakeSafetyRepository safety, String tapLabel) async {
      returned = 'not-returned';
      await tester.pumpWidget(ProviderScope(
        overrides: [
          safetyRepositoryProvider.overrideWithValue(safety),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async => returned = await blockThenLeave(context, ref, profileId: 'p2', nickname: '토끼'),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tapLabel));
      await tester.pumpAndSettle();
    }

    testWidgets('차단 요청이 실패하면 글자가 아니라 그 Failure 를 돌려준다', (tester) async {
      await openAndTap(tester, FakeSafetyRepository()..blockResult = const FailureResult(NetworkFailure()), '차단');

      expect(returned, isA<NetworkFailure>());
    });

    testWidgets('차단에 성공하면 null 이다', (tester) async {
      final safety = FakeSafetyRepository();
      await openAndTap(tester, safety, '차단');

      expect(safety.blocked, ['p2']);
      expect(returned, isNull);
    });

    testWidgets('확인 시트에서 취소하면 차단하지 않고 null 이다', (tester) async {
      final safety = FakeSafetyRepository();
      await openAndTap(tester, safety, '취소');

      expect(safety.blocked, isEmpty);
      expect(returned, isNull);
    });
  });
}
