import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';
import 'package:campus_mate/matching/view/notification_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

void main() {
  Future<FakeCardRepository> pump(WidgetTester tester) async {
    final repository = FakeCardRepository()
      ..preferences = const Success(NotificationPreferences());
    final container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
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

  testWidgets('스위치를 끄면 그 키만 서버로 간다', (tester) async {
    final repository = await pump(tester);

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump();

    expect(repository.preferenceUpdates.single, (key: 'card_arrived', value: false));
  });
}
