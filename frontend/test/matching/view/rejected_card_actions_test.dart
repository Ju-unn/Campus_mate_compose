import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/matching/model/data/acceptance.dart';
import 'package:campus_mate/matching/model/data/card_detail.dart';
import 'package:campus_mate/matching/model/data/card_profile.dart';
import 'package:campus_mate/matching/model/data/rejected_card.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/matching/view/rejected_card_actions.dart';
import 'package:campus_mate/matching/viewmodel/acceptance_detail_view_model.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/repository/fake_card_repository.dart';

const _rows = Success(RejectedCards([
  RejectedCard(cardId: 'card-1', source: RejectedSource.card, daysLeft: 5, profile: CardProfile(nickname: '여우비', age: 23)),
  RejectedCard(cardId: 'card-2', source: RejectedSource.acceptance, daysLeft: 2, profile: CardProfile(nickname: '봄비', age: 22)),
]));

/// 거절한 카드 · 프로필 보기 아래 버튼(pen hhlWE DJ46i: 폭 꽉 · 56 · primary · 모서리 8 · heart 20 + 18/700).
/// 받은 신청 출처는 [수락하기](사용자 선택, 대장 확정 11-24) — 팝업 없이 바로 매칭 화면.
void main() {
  Future<FakeCardRepository> pump(
    WidgetTester tester,
    RejectedSource source, {
    FakeCardRepository? fake,
    Result<RejectedCards> rows = _rows,
  }) async {
    final repository = (fake ?? FakeCardRepository())..rejected = rows;
    final cardId = source == RejectedSource.card ? 'card-1' : 'card-2';
    final container = ProviderContainer(overrides: [cardRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/list',
      routes: [
        GoRoute(
          path: '/list',
          builder: (context, state) => TextButton(
            onPressed: () async {
              final sent = await context.push<bool>('/profile');
              lastPopped = sent;
            },
            child: const Text('목록'),
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => Scaffold(body: RejectedProfileAction(cardId: cardId, source: source)),
        ),
        GoRoute(
          path: AppRoutes.matchMade,
          builder: (context, state) => Text('매칭 ${(state.extra as MatchMadeArgs?)?.nickname}'),
        ),
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();
    return repository;
  }

  setUp(() => lastPopped = null);

  testWidgets('내 카드 거절: 폭 꽉 · 56 · primary · 작은 크기(모서리 8 · 18/700) · 하트 20 + "다시 신청하기"', (tester) async {
    await pump(tester, RejectedSource.card);

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect((button.label, button.variant, button.size, button.height), ('다시 신청하기', AppButtonVariant.primary, AppButtonSize.small, 56.0));
    final heart = tester.widget<Icon>(find.descendant(of: find.byType(AppButton), matching: find.byType(Icon)));
    expect((heart.icon, heart.size), (AppIcons.heart, 20.0));
  });

  testWidgets('확인 팝업에서 [신청하기] → 다시 신청을 보내고 참을 들고 목록으로 돌아간다', (tester) async {
    final repository = await pump(tester, RejectedSource.card);

    await tester.tap(find.text('다시 신청하기'));
    await tester.pumpAndSettle();
    expect(find.text('다시 대화를 신청할까요?'), findsOneWidget);
    await tester.tap(find.text('신청하기'));
    await tester.pumpAndSettle();

    expect(repository.reappliedCardIds, ['card-1']);
    expect(lastPopped, isTrue);
    expect(find.text('목록'), findsOneWidget);
  });

  testWidgets('[취소] 면 보내지 않고 그 화면에 남는다', (tester) async {
    final repository = await pump(tester, RejectedSource.card);

    await tester.tap(find.text('다시 신청하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(repository.reappliedCardIds, isEmpty);
    expect(find.byType(RejectedProfileAction), findsOneWidget);
  });

  testWidgets('보내기가 거절되면 그 화면에 남아 서버 문구를 스낵바로 보인다', (tester) async {
    await pump(
      tester,
      RejectedSource.card,
      fake: FakeCardRepository()..reapplyResult = const FailureResult(ServerRejectedFailure('카드를 찾을 수 없어요')),
    );

    await tester.tap(find.text('다시 신청하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신청하기'));
    await tester.pumpAndSettle();

    expect(find.byType(RejectedProfileAction), findsOneWidget);
    expect(find.text('카드를 찾을 수 없어요'), findsOneWidget);
  });

  testWidgets('앞선 실패 문구가 남아 있어도 [취소] 면 스낵바를 다시 띄우지 않는다', (tester) async {
    await pump(
      tester,
      RejectedSource.card,
      fake: FakeCardRepository()..reapplyResult = const FailureResult(ServerRejectedFailure('카드를 찾을 수 없어요')),
    );
    await tester.tap(find.text('다시 신청하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신청하기'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10)); // 첫 스낵바가 사라질 때까지
    await tester.pumpAndSettle();
    expect(find.text('카드를 찾을 수 없어요'), findsNothing);

    await tester.tap(find.text('다시 신청하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.text('카드를 찾을 수 없어요'), findsNothing);
  });

  testWidgets('받은 신청 거절: [수락하기](체크) — 팝업 없이 되돌리고 이 화면 자리에 매칭 화면(12)', (tester) async {
    final repository = await pump(tester, RejectedSource.acceptance);

    final icon = tester.widget<Icon>(find.descendant(of: find.byType(AppButton), matching: find.byType(Icon)));
    expect(icon.icon, AppIcons.check);
    await tester.tap(find.text('수락하기'));
    await tester.pumpAndSettle();

    expect(repository.undoneCardIds, ['card-2']);
    expect(find.text('다시 대화를 신청할까요?'), findsNothing);
    expect(find.text('매칭 봄비'), findsOneWidget);
  });

  testWidgets('목록에 그 줄이 없어도 프로필 화면이 읽은 닉네임으로 매칭 화면(12)에 간다', (tester) async {
    final detail = CardDetail(
      cardId: 'card-2',
      profile: const CardProfile(nickname: '봄비', age: 22),
      survey: List.filled(9, 0.5),
      animalType: AnimalType.cat,
      impressionType: ImpressionType.chic,
      religion: Religion.none,
      isSmoker: false,
      interests: const [],
      myTraits: const [],
      idealTraits: const [],
    );
    await pump(
      tester,
      RejectedSource.acceptance,
      fake: FakeCardRepository()..acceptanceDetail = Success(detail),
      rows: const Success(RejectedCards.empty),
    );
    // 실제 화면(ReadOnlyProfileScreen)은 같은 키를 watch 한다 — 그 자리를 대신 붙잡는다.
    final container = ProviderScope.containerOf(tester.element(find.byType(RejectedProfileAction)));
    final keep = container.listen(acceptanceDetailViewModelProvider('card-2'), (_, _) {});
    addTearDown(keep.close);
    await tester.pumpAndSettle();

    await tester.tap(find.text('수락하기'));
    await tester.pumpAndSettle();

    expect(find.text('매칭 봄비'), findsOneWidget);
  });
}

bool? lastPopped;
