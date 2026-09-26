import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/mosaic_tile.dart';
import 'package:campus_mate/home/view/tag.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../model/fake_home_repository.dart';

/// mosaic-rail 도 가로 Scrollable 이라 세로 목록을 짚어 준다.
final _mainList = find.byType(Scrollable).first;

void main() {
  const summary = HomeSummary(
    unreadNotifications: 7,
    presentPeopleImages: ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png'],
    deliveredCards: 1234567,
    signups: 862,
    conversationsStarted: 391,
    reviewRating: 4.6,
    reviewCount: 57,
    campuses: ['가람대', '새솔대'],
    profileCompletionPercent: 40,
  );

  Future<void> pump(WidgetTester tester, [Result<HomeSummary> result = const Success(summary)]) async {
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(result)),
        // 하단 내비 뱃지가 수락 대기·안 읽은 메시지를 읽는다(§8.8).
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
        GoRoute(path: AppRoutes.today, builder: (context, state) => const Text('오늘 탭')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  testWidgets('hero-today 의 "지금 확인하기"를 누르면 오늘 탭으로 간다', (tester) async {
    await pump(tester);

    expect(find.text('오늘의 카드가'), findsOneWidget);
    expect(find.text('도착했어요'), findsOneWidget);
    await tester.tap(find.text('지금 확인하기'));
    await tester.pumpAndSettle();

    expect(find.text('오늘 탭'), findsOneWidget);
  });

  testWidgets('stat-panel 은 저장소 숫자를 세 자리 쉼표로 보여준다', (tester) async {
    await pump(tester);

    expect(find.text('1,234,567'), findsOneWidget);
    expect(find.text('862'), findsOneWidget);
    expect(find.text('391'), findsOneWidget);
    expect(find.text('전달된 카드'), findsOneWidget);
    expect(find.text('가입 수'), findsOneWidget);
    expect(find.text('시작된 대화'), findsOneWidget);
  });

  testWidgets('review-strip 은 평점과 평가 수를 보여준다', (tester) async {
    await pump(tester);

    expect(find.text('4.6'), findsOneWidget);
    expect(find.text('(57명 평가)'), findsOneWidget);
    expect(find.text('리뷰 남기기'), findsOneWidget);
  });

  testWidgets('campus-strip 은 저장소의 대학을 태그 하나씩 보여준다', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('참여 중인 대학'), 200, scrollable: _mainList);

    expect(find.text('가람대'), findsOneWidget);
    expect(find.text('새솔대'), findsOneWidget);
    // pen `zOaUW` 은 태그를 한 줄에 옆으로 늘어놓는다 — 태그가 폭을 다 먹으면 세로로 쌓인다.
    expect(tester.getTopLeft(find.text('새솔대')).dy, tester.getTopLeft(find.text('가람대')).dy);
  });

  testWidgets('mosaic-rail 은 사람 수만큼 칸을 두고 끝에 빈 칸 하나를 붙인다', (tester) async {
    await pump(tester);

    expect(find.text('지금 함께 있는 사람들'), findsOneWidget);
    expect(find.byType(MosaicPersonTile), findsNWidgets(2));
    expect(find.text('아직 비어 있어요'), findsOneWidget);
  });

  testWidgets('앱바 알림 종에 안 읽은 알림 수를 붙인다', (tester) async {
    await pump(tester);

    expect(find.text('CampusMate'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('프로필 완성도 카드는 저장소의 퍼센트를 보여준다', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

    expect(find.text('프로필 완성도 40%'), findsOneWidget);
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('pen 프레임 크기(360×884)·글자 배율 $scale 에서 어느 줄도 넘치지 않는다', (tester) async {
      // 테스트 글꼴은 한글이 Pretendard 보다 넓다 — 여기서 버티면 실제 폰에서도 버틴다.
      tester.view.physicalSize = const Size(360, 884);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester);
      await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('글자 배율 2.0 에서 본문 글자가 고정 상자에 잘리지 않는다', (tester) async {
    // 넘침 오류는 Flex 만 낸다 — SizedBox·Container 높이에 갇힌 글자는 오류 없이 잘린다.
    tester.view.physicalSize = const Size(360, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 앱바·내비까지 화면 전체를 본다. 내비 "커뮤니티" 는 칸 폭 안에서 일부러 말줄임한다.
    List<String> clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.text.toPlainText() != '커뮤니티' &&
                (p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                    p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
          p.text.toPlainText(),
    ];

    await pump(tester);
    final clipped = clippedTexts();
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);
    clipped.addAll(clippedTexts());
    // 넘침은 위 배율 테스트가 본다 — 여기서는 잘림만 본다.
    tester.takeException();

    expect(clipped, isEmpty);
  });

  testWidgets('pen 좌표와 같다 — hero 버튼 y158 · 태그 y647 · 카드 y691 · 빈 칸 글자 x14', (tester) async {
    // pen `bpA8x` 값(앱바 56 포함). 글자 상자 높이 hero 29(`dIoz0`)·대학 제목 20(`YIoXQ`)은 렌더 결과(lineHeight 속성 없음), 빈 칸 글자 x14(`FqMYC`).
    tester.view.physicalSize = const Size(360, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester);

    final heroButton = find.ancestor(of: find.text('지금 확인하기'), matching: find.byType(InkWell));
    expect(tester.getTopLeft(heroButton).dy, 158);
    expect(tester.getTopLeft(find.byType(Tag).first).dy, 647);
    final nudge = find.ancestor(of: find.text('사진을 한 장 더 올리면'), matching: find.byType(Container)).last;
    expect(tester.getTopLeft(nudge).dy, 691);
    final emptyTile = tester.getTopLeft(find.byType(MosaicEmptyTile));
    expect(tester.getTopLeft(find.text('아직 비어 있어요')).dx - emptyTile.dx, 14);
  });

  testWidgets('review-strip 별은 AppIcons.star 다섯 개다', (tester) async {
    await pump(tester);

    expect(find.byIcon(AppIcons.star), findsNWidgets(5));
  });

  testWidgets('요약을 못 받아도 hero-today 는 남는다', (tester) async {
    await pump(tester, const FailureResult(NetworkFailure()));

    expect(find.text('지금 확인하기'), findsOneWidget);
    expect(find.text('전달된 카드'), findsNothing);
  });
}
