import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_balance_chip.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/cohort_wait.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../model/fake_home_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';

/// 홈 앱바의 하트 잔액 칩 — pen `Trailing`(홈 6곳: `bpA8x` · `lvmAj` · `l1120` · `fATGt` · `U9fmK` · `BZ9WY`) = 칩(`sysyz` 인스턴스, "+" 켬, 높이 44) · gap 4 · 종.
/// 앱바는 어느 상태에서나 같은 한 줄이다 — 요약 읽는 중 · 보통 · 숫자 0 빈 판 · 완성도 100 · 코호트 대기에서 자리가 같은지 본다(pen 은 6곳이 같은 값).
MyProfile _profile(int hearts) => MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: '경영학과',
  heightCm: 178,
  mbti: 'ENFP',
  avatarUrl: null,
  photos: const [],
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: 165,
  preferredHeightMax: 180,
  bio: '',
  heartBalance: hearts,
  avatarRegenCost: 10,
);

void main() {
  const summary = HomeSummary(
    presentPeopleImages: ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png'],
    deliveredCards: 10,
    signups: 20,
    conversationsStarted: 30,
    reviewRating: 4.6,
    reviewCount: 57,
    campuses: ['가람대'],
    profileCompletionPercent: 40,
  );

  late FakeMeRepository me;

  /// [settle] 이 false 면 첫 프레임만 그린다(요약 · 잔액을 읽는 중).
  Future<void> pump(
    WidgetTester tester, {
    Result<MyProfile>? profile,
    HomeSummary data = summary,
    bool settle = true,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(360, 884); // pen 프레임
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    me = FakeMeRepository(profile ?? Success(_profile(320)));
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(Success(data))),
        notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        meRepositoryProvider.overrideWithValue(me),
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
        GoRoute(path: AppRoutes.heartStore, builder: (context, state) => const Text('하트 상점')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    if (settle) await tester.pump();
  }

  final chip = find.byType(HeartBalanceChipView);
  // 눈에 보이는 띠(44) — 칩 상자는 투명한 눌림 칸까지 48 이다(위 4 · 띠는 y6).
  final band = find.descendant(of: chip, matching: find.byType(Material)).first;
  final bell = find.byType(NotifyIconButton);

  HomeSummary withSummary({int? percent, int? delivered, int? signups, int? conversations, CohortWait? cohort}) =>
      HomeSummary(
        presentPeopleImages: summary.presentPeopleImages,
        deliveredCards: delivered ?? summary.deliveredCards,
        signups: signups ?? summary.signups,
        conversationsStarted: conversations ?? summary.conversationsStarted,
        reviewRating: summary.reviewRating,
        reviewCount: summary.reviewCount,
        campuses: summary.campuses,
        profileCompletionPercent: percent ?? summary.profileCompletionPercent,
        cohort: cohort,
      );

  /// 칩 오른쪽 끝 x300(종 칸 304 − 4) · 위 6 · 높이 44, 종 칸은 x304 · 48×48 · 위 4.
  void expectTrailing(WidgetTester tester) {
    expect(find.text('320'), findsOneWidget);
    expect(tester.getTopRight(band), const Offset(300, 6));
    expect(tester.getSize(band).height, 44);
    expect(tester.getTopRight(chip), const Offset(300, 4)); // 눌림 칸 48 — 띠 위 2 가 투명하다
    expect(tester.getSize(chip).height, 48);
    expect(tester.getTopLeft(bell), const Offset(304, 4));
    expect(tester.getSize(bell), const Size(48, 48));
    expect(tester.getTopLeft(bell).dx - tester.getTopRight(band).dx, 4);
  }

  group('칩 자리 — pen `Trailing`', () {
    testWidgets('칩이 종 바로 왼쪽에 있다: 오른쪽 끝 x300 · 위 6 · 높이 44 · 종과 사이 4', (tester) async {
      await pump(tester);
      expectTrailing(tester);
    });

    testWidgets('"+" 를 켠 모양이다(칩 폭이 "+" 없는 칩보다 22 넓다 = gap 6 + 아이콘 16)', (tester) async {
      await pump(tester);
      final view = tester.widget<HeartBalanceChipView>(chip);
      expect((view.showPlus, view.balance), (true, 320));
      final digits = tester.getSize(find.text('320')).width;
      expect(tester.getSize(band).width, 8 + 24 + 6 + digits + 6 + 16 + 12);
    });

    testWidgets('제목은 칩 · 종이 쓰고 남은 왼쪽에서 x20 부터 시작하고 칩과 겹치지 않는다', (tester) async {
      await pump(tester);
      final title = find.text('CampusMate');
      expect(tester.getTopLeft(title).dx, 20);
      expect(tester.getTopRight(title).dx, lessThanOrEqualTo(tester.getTopLeft(chip).dx));
    });

    testWidgets('앱바 높이는 56 그대로다', (tester) async {
      await pump(tester);
      expect(tester.getSize(find.byType(AppBar)).height, 56);
    });
  });

  group('6개 홈 상태에서 같은 자리', () {
    final states = <String, HomeSummary>{
      '보통': summary,
      '숫자가 모두 0 인 빈 판': withSummary(delivered: 0, signups: 0, conversations: 0),
      '완성도 100(카드 숨김)': withSummary(percent: 100),
      '코호트 대기': withSummary(cohort: CohortWait(firstCardAt: DateTime.now().add(const Duration(days: 3)), recruitCount: 5)),
    };
    for (final entry in states.entries) {
      testWidgets('[${entry.key}] 칩 · 종이 같은 자리', (tester) async {
        await pump(tester, data: entry.value);
        expectTrailing(tester);
        expect(tester.getSize(find.byType(AppBar)).height, 56);
      });
    }

    testWidgets('[요약을 읽는 중] 칩이 잔액이 오는 대로 뜨고 종은 자리를 지킨다', (tester) async {
      await pump(tester, settle: false);
      expect(tester.getTopLeft(bell), const Offset(304, 4));
      expect(tester.getSize(find.byType(AppBar)).height, 56);

      await tester.pump();
      expectTrailing(tester);
    });
  });

  group('잔액을 못 읽을 때 앱바가 흔들리지 않는다', () {
    testWidgets('읽는 중에는 칩이 없고 종 · 제목 자리는 칩이 있을 때와 같다', (tester) async {
      await pump(tester, settle: false);
      expect(chip, findsNothing);
      expect(tester.getTopLeft(bell), const Offset(304, 4));
      expect(tester.getTopLeft(find.text('CampusMate')).dx, 20);
      expect(tester.getSize(find.byType(AppBar)).height, 56);
    });

    testWidgets('읽기에 실패하면 칩이 없고 종은 그대로다', (tester) async {
      await pump(tester, profile: const FailureResult(NetworkFailure()));
      expect(chip, findsNothing);
      expect(tester.getTopLeft(bell), const Offset(304, 4));
      expect(tester.getSize(find.byType(AppBar)).height, 56);
    });
  });

  group('"+"', () {
    testWidgets('누르면 하트 상점(`/hearts/store`)으로 간다 — "곧 열려요" 는 더 이상 나오지 않는다', (tester) async {
      await pump(tester);

      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.text('하트 상점'), findsOneWidget);
      expect(find.text('곧 열려요'), findsNothing);
    });

    testWidgets('"+" 를 프레임 없이 두 번 눌러도 상점은 한 겹만 쌓인다', (tester) async {
      await pump(tester);

      await tester.tap(chip);
      await tester.tap(chip); // 첫 누름이 만든 길이 아직 그려지기 전 — 두 번째 누름도 칩에 닿는다
      await tester.pumpAndSettle();

      expect(find.text('하트 상점', skipOffstage: false), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(); // 돌아오면 잔액을 다시 읽어 pumpAndSettle 은 끝나지 않는다 — 몇 프레임만
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(HomeScreen), findsOneWidget); // 한 번 닫으면 홈이다(두 겹이면 상점이 남는다)
      expect(find.text('하트 상점'), findsNothing);
    });

    testWidgets('상점을 닫은 뒤에는 "+" 를 다시 눌러 열 수 있다', (tester) async {
      await pump(tester);

      await tester.tap(chip);
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(); // 돌아오면 잔액을 다시 읽어 pumpAndSettle 은 끝나지 않는다 — 몇 프레임만
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.text('하트 상점'), findsOneWidget);
    });

    testWidgets('띠 위 투명한 눌림 칸(띠에서 1px 위)을 눌러도 상점으로 간다', (tester) async {
      await pump(tester);

      await tester.tapAt(Offset(tester.getRect(band).center.dx, tester.getTopLeft(band).dy - 1));
      await tester.pumpAndSettle();

      expect(find.text('하트 상점'), findsOneWidget);
    });

    testWidgets('상점에서 돌아오면 잔액을 다시 읽는다', (tester) async {
      await pump(tester);
      expect(me.calls, 1);

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(me.calls, 1); // 상점에 있는 동안은 다시 읽지 않는다

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(me.calls, 2);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('칩은 홈 위젯이 새로 그린 것이 아니라 공용 HeartBalanceChip 이다', (tester) async {
      await pump(tester);
      expect(find.byType(HeartBalanceChip), findsOneWidget);
    });

    testWidgets('스크린리더 힌트에 "하트 충전" 이 붙는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(tester.getSemantics(chip).getSemanticsData().hint, '하트 충전');
      handle.dispose();
    });
  });

  group('글자를 키워도', () {
    for (final scale in [1.5, 2.0]) {
      testWidgets('배율 $scale — 칩 높이 44 · 종 자리는 그대로고 제목이 칩을 덮거나 잘리지 않는다', (tester) async {
        await pump(tester, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(tester.getSize(band).height, 44);
        expect(tester.getTopRight(band), const Offset(300, 6));
        expect(tester.getTopLeft(bell), const Offset(304, 4));
        final title = find.text('CampusMate');
        expect(tester.getTopRight(title).dx, lessThanOrEqualTo(tester.getTopLeft(chip).dx));
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(paragraph.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(paragraph.size.width + 0.5));
      });
    }
  });
}
