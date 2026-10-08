import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('준비 중 화면의 톱니', () {
    Future<void> pumpTab(WidgetTester tester, AppTab tab) async {
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ComingSoonScreen(tab: tab)),
        ),
      );
      await tester.pump();
    }

    // 설정(16)으로 가는 문은 15 내 프로필(`nkFJV`) 톱니 하나뿐이고 그 화면이 생겼다 — 준비 중 화면엔 어느 탭이든 톱니가 없다.
    for (final tab in [AppTab.community, AppTab.me]) {
      testWidgets('${tab.name} 탭 준비 중 화면에는 톱니가 없다', (tester) async {
        await pumpTab(tester, tab);

        expect(find.byIcon(AppIcons.settings), findsNothing);
      });
    }
  });
}
