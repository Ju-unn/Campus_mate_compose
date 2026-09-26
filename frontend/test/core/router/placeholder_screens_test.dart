import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('스플래시 화면은 스피너 없이 마스코트·빨간 "CampusMate"·부제를 보인다(pen jXJSY)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('하루 한 사람, 같은 캠퍼스에서'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final text = tester.widget<Text>(find.text('CampusMate'));
    expect(text.style?.fontSize, AppTypography.display.fontSize);
    expect(text.style?.color, AppColors.primary);
  });

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

    // 설정(16)으로 가는 문은 15 내 프로필(`r8oJc`) 톱니 하나뿐이고 그 화면이 생겼다 — 준비 중 화면엔 어느 탭이든 톱니가 없다.
    for (final tab in [AppTab.community, AppTab.me]) {
      testWidgets('${tab.name} 탭 준비 중 화면에는 톱니가 없다', (tester) async {
        await pumpTab(tester, tab);

        expect(find.byIcon(AppIcons.settings), findsNothing);
      });
    }
  });
}
