import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/repository/home_repository_provider.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/matching/model/data/card_profile.dart';
import 'package:campus_mate/matching/model/data/daily_card.dart';
import 'package:campus_mate/matching/model/data/rejected_card.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/matching/view/countdown_text.dart';
import 'package:campus_mate/matching/view/today_cards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/repository/fake_chat_repository.dart';
import '../../home/model/repository/fake_home_repository.dart';
import '../model/repository/fake_card_repository.dart';

const _rejected = Success(RejectedCards([
  RejectedCard(
    cardId: 'card-1',
    source: RejectedSource.card,
    daysLeft: 5,
    profile: CardProfile(nickname: '여우비', age: 23),
  ),
]));

/// 카드 대기 화면 [거절한 카드 다시 보기](pen 25-G i2gRJO `GyA9i`, UI값표 CT5Lq 20-1) — 7일 안 거절이 있을 때만,
/// 카운트다운 → 24 → 버튼 44(surface-strong · ink 16/700 · 모서리 14) → 14 → 마스코트. 누르면 대화 탭 [거절한 카드].
void main() {
  Future<void> pump(WidgetTester tester, FakeCardRepository repository) async {
    repository.today = Success(TodayCards(cards: const [], nextIssueAt: DateTime.now().add(const Duration(hours: 3))));
    final container = ProviderContainer(overrides: [
      cardRepositoryProvider.overrideWithValue(repository),
      chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.today,
      routes: [
        GoRoute(path: AppRoutes.today, builder: (context, state) => const TodayCardsScreen()),
        GoRoute(path: AppRoutes.conversations, builder: (context, state) => Text('대화 ${state.uri}')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Finder button() => find.ancestor(of: find.text('거절한 카드 다시 보기'), matching: find.byType(AppButton));

  Finder mascot() => find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is AssetImage && (widget.image as AssetImage).assetName == 'assets/images/mascot-male-waiting.webp',
      );

  testWidgets('거절한 카드가 없으면 버튼이 없고 카운트다운 → 24 → 마스코트 그대로', (tester) async {
    await pump(tester, FakeCardRepository());

    expect(button(), findsNothing);
    expect(tester.getRect(mascot()).top - tester.getRect(find.byType(CountdownText)).bottom, 24);
  });

  testWidgets('있으면 카운트다운 → 24 → 버튼 44 → 14 → 마스코트, 보조 회색(tonal) 버튼', (tester) async {
    await pump(tester, FakeCardRepository()..rejected = _rejected);

    // 보이는 상자(버튼의 Material). 누르는 칸은 위아래 2 씩 더 큰 48 이다.
    final rect = tester.getRect(find.descendant(of: button(), matching: find.byType(Material)).first);
    expect(rect.top - tester.getRect(find.byType(CountdownText)).bottom, 24);
    expect(rect.height, 44);
    expect(tester.getRect(mascot()).top - rect.bottom, 14);
    expect(tester.widget<AppButton>(button()).variant, AppButtonVariant.tonal);
    final label = tester.widget<Text>(find.text('거절한 카드 다시 보기'));
    expect((label.style?.fontSize, label.style?.fontWeight), (16, FontWeight.w700));
  });

  testWidgets('누르면 대화 탭을 [거절한 카드] 로 연다', (tester) async {
    await pump(tester, FakeCardRepository()..rejected = _rejected);

    await tester.tap(button());
    await tester.pumpAndSettle();

    expect(find.text('대화 /conversations?tab=rejected'), findsOneWidget);
  });
}
