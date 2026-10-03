import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/cohort_wait.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/mosaic_tile.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
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
    presentPeopleImages: ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png'],
    deliveredCards: 1234567,
    signups: 862,
    conversationsStarted: 391,
    reviewRating: 4.6,
    reviewCount: 57,
    campuses: ['가람대', '새솔대'],
    profileCompletionPercent: 40,
  );

  HomeSummary summaryWith({int? delivered, int? signups, int? conversations, int? percent}) => HomeSummary(
    presentPeopleImages: summary.presentPeopleImages,
    deliveredCards: delivered ?? summary.deliveredCards,
    signups: signups ?? summary.signups,
    conversationsStarted: conversations ?? summary.conversationsStarted,
    reviewRating: summary.reviewRating,
    reviewCount: summary.reviewCount,
    campuses: summary.campuses,
    profileCompletionPercent: percent ?? summary.profileCompletionPercent,
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

  /// 기본 테스트 화면(800×600)에선 리뷰 띠가 화면 밖이다 — pen 프레임으로 본다.
  void penFrame(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('review-strip 은 평점과 평가 수를 보여준다', (tester) async {
    penFrame(tester);
    await pump(tester);

    expect(find.text('4.6'), findsOneWidget);
    expect(find.text('(57명 평가)'), findsOneWidget);
    expect(find.text('리뷰 남기기'), findsOneWidget);
  });

  testWidgets('버튼 글자 — 히어로 `YiLtq` 18/700 · 리뷰 `ifX9K` 16/700', (tester) async {
    penFrame(tester);
    await pump(tester);

    final hero = tester.widget<Text>(find.text('지금 확인하기')).style!;
    expect((hero.fontSize, hero.fontWeight), (18, FontWeight.w700));
    final review = tester.widget<Text>(find.text('리뷰 남기기')).style!;
    expect((review.fontSize, review.fontWeight), (16, FontWeight.w700));
  });

  testWidgets('campus-strip 은 저장소의 대학을 태그 하나씩 보여준다', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('참여 중인 대학'), 200, scrollable: _mainList);

    expect(find.text('가람대'), findsOneWidget);
    expect(find.text('새솔대'), findsOneWidget);
    // pen `zOaUW` 은 태그를 한 줄에 옆으로 늘어놓는다 — 태그가 폭을 다 먹으면 세로로 쌓인다.
    expect(tester.getTopLeft(find.text('새솔대')).dy, tester.getTopLeft(find.text('가람대')).dy);
  });

  testWidgets('mosaic-rail 은 사람 수만큼 칸 뒤에 빈 칸 하나를 붙인 한 벌을 되풀이한다', (tester) async {
    await pump(tester);

    expect(find.text('지금 함께 있는 사람들'), findsOneWidget);
    final people = find.byType(MosaicPersonTile).evaluate().length;
    final empties = find.byType(MosaicEmptyTile).evaluate().length;
    expect(empties, greaterThanOrEqualTo(2));
    expect(people, 2 * empties);
  });

  testWidgets('mosaic-rail 머리줄에 "일시정지"(pen `Ab3td` 오른쪽)는 없다 — 사용자 결정 2026-09-26', (tester) async {
    await pump(tester);

    expect(find.text('일시정지'), findsNothing);
    expect(find.byIcon(AppIcons.pause), findsNothing);
  });

  group('mosaic-rail 자동 흐름', () {
    double railX(WidgetTester tester) => tester.getTopLeft(find.byType(MosaicPersonTile).first).dx;

    testWidgets('시간이 지나면 칸이 오른쪽으로 움직인다', (tester) async {
      await pump(tester);
      final before = railX(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(railX(tester), greaterThan(before));
    });

    testWidgets('누르고 있으면 멈추고, 떼면 다시 흐른다', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(MosaicRail)));
      await tester.pump(const Duration(milliseconds: 100));
      final held = railX(tester);

      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), held);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), greaterThan(held));
    });

    testWidgets('두 손가락 중 하나만 떼면 여전히 멈춰 있다', (tester) async {
      // 레일만 띄운다. 홈 목록 안에서는 첫 손가락이 목록 끌기를 시작해 목록이 자식을 IgnorePointer 로
      // 막으므로 둘째 손가락이 레일에 닿지 않는다(Flutter DragScrollActivity.shouldIgnorePointer) — 위젯 약속으로 고정한다.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MosaicRail(images: ['assets/images/person-f1-blind-v1.png']))),
      );
      final center = tester.getCenter(find.byType(MosaicRail));
      final first = await tester.startGesture(center);
      final second = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await second.up();
      await tester.pump();
      final held = railX(tester);

      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), held);

      await first.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), greaterThan(held));
    });

    testWidgets('움직이는 칸 묶음은 RepaintBoundary 안에 있다 — 매 프레임 옮기기만 하고 다시 그리지 않는다', (tester) async {
      await pump(tester);

      final boundary = find.descendant(
        of: find.descendant(of: find.byType(MosaicRail), matching: find.byType(Transform)),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundary, findsOneWidget);
      expect(tester.widget<RepaintBoundary>(boundary).child, isA<IntrinsicHeight>());
    });

    testWidgets('화면 읽기는 되풀이한 칸을 한 벌만 읽는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      // 목록 칸 글자는 한 의미 노드로 합쳐진다 — 그 안에 빈 칸 글자가 한 번만 있어야 한다.
      final label = tester.getSemantics(find.bySemanticsLabel(RegExp('아직 비어 있어요'))).label;
      semantics.dispose();
      expect('아직 비어 있어요'.allMatches(label).length, 1);
    });

    testWidgets('기기 "애니메이션 줄이기"가 켜져 있으면 흐르지 않는다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pump(tester);
      final before = railX(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(railX(tester), before);
    });
  });

  testWidgets('앱바 알림 종에 숫자 배지를 달지 않는다 — 알림함이 생길 때까지(사용자 결정 2026-09-26)', (tester) async {
    await pump(tester);

    expect(find.text('CampusMate'), findsOneWidget);
    expect(find.byType(NotifyIconButton), findsOneWidget);
    expect(find.descendant(of: find.byType(NotifyIconButton), matching: find.byType(Text)), findsNothing);
  });

  testWidgets('프로필 완성도 카드는 저장소의 퍼센트를 보여준다', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

    expect(find.text('프로필 완성도 40%'), findsOneWidget);
    // 문구는 사용자 결정 2026-09-26(pen `tV9Oa` · `KjqWO`).
    expect(find.text('프로필을 조금 더 채우면'), findsOneWidget);
    expect(find.text('나를 더 잘 보여 줄 수 있어요'), findsOneWidget);
  });

  testWidgets('완성도 카드 글자 상자는 pen 과 같다 — y7.5·32.5·68.5, 높이 20·20·16(`usk5M`, lineHeight 속성 없음 렌더 결과)', (tester) async {
    // 세로 좌표만 본다. 테스트 글꼴은 둘째 줄이 238 이라 pen 폭(360)의 글자 칸 192 에서 접힌다
    // (Pretendard 는 pen `KjqWO` 폭 164) — 접히지 않게 화면만 넓힌다.
    tester.view.physicalSize = const Size(420, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);

    final card = find.ancestor(of: find.text('프로필을 조금 더 채우면'), matching: find.byType(Container)).last;
    final top = tester.getTopLeft(card).dy;
    for (final (text, y, height) in [
      ('프로필을 조금 더 채우면', 7.5, 20.0),
      ('나를 더 잘 보여 줄 수 있어요', 32.5, 20.0),
      ('프로필 완성도 40%', 68.5, 16.0),
    ]) {
      expect(tester.getTopLeft(find.text(text)).dy - top, y, reason: text);
      expect(tester.getSize(find.text(text)).height, height, reason: text);
    }
    expect(tester.getSize(card).height, 92);
  });

  testWidgets('완성도가 100 이면 완성도 카드를 숨긴다', (tester) async {
    await pump(tester, Success(summaryWith(percent: 100)));
    await tester.scrollUntilVisible(find.text('참여 중인 대학'), 200, scrollable: _mainList);
    await tester.drag(_mainList, const Offset(0, -500));
    await tester.pump();

    expect(find.textContaining('프로필 완성도'), findsNothing);
  });

  group('세 숫자가 모두 0 이면 숫자 칸 대신 빈 상태 판(pen `Tklrw` · `AJVDS`)', () {
    testWidgets('세 숫자가 모두 0 이면 판이 보이고 숫자 칸은 없다', (tester) async {
      await pump(tester, Success(summaryWith(delivered: 0, signups: 0, conversations: 0)));

      expect(find.text('첫 기록이 쌓이는 중이에요'), findsOneWidget);
      expect(find.text('전달된 카드'), findsNothing);
      expect(find.text('가입 수'), findsNothing);
      expect(find.text('시작된 대화'), findsNothing);
      // 다른 칸은 그대로다. 판이 숫자 칸보다 높아 리뷰 줄은 스크롤해야 보인다.
      expect(find.text('지금 함께 있는 사람들'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('리뷰 남기기'), 200, scrollable: _mainList);
      expect(find.text('리뷰 남기기'), findsOneWidget);
    });

    for (final (delivered, signups, conversations) in [(1, 0, 0), (0, 1, 0), (0, 0, 1)]) {
      testWidgets('하나라도 0 보다 크면 숫자 칸을 보여 준다 ($delivered, $signups, $conversations)', (tester) async {
        await pump(tester, Success(summaryWith(delivered: delivered, signups: signups, conversations: conversations)));

        expect(find.text('첫 기록이 쌓이는 중이에요'), findsNothing);
        expect(find.text('전달된 카드'), findsOneWidget);
      });
    }

    testWidgets('pen 값과 같다 — 판 폭은 숫자 칸 자리 그대로, 높이 124, 마스코트 72 y12 가운데, 문구 y92 높이 20', (tester) async {
      tester.view.physicalSize = const Size(360, 884);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, Success(summaryWith(delivered: 0, signups: 0, conversations: 0)));

      final text = find.text('첫 기록이 쌓이는 중이에요');
      final panel = find.ancestor(of: text, matching: find.byType(DecoratedBox)).first;
      final mascot = find.descendant(of: panel, matching: find.byType(Image));
      final origin = tester.getTopLeft(panel);
      expect(tester.getSize(panel), const Size(328, 124));
      expect(tester.getSize(mascot), const Size(72, 72));
      // `U3fkT0` = 마스터 `J2kzx` "Mascot Male · Blue Scarf".
      expect((tester.widget<Image>(mascot).image as AssetImage).assetName, 'assets/images/mascot-male.png');
      expect(tester.getTopLeft(mascot) - origin, const Offset(128, 12));
      expect(tester.getTopLeft(text).dy - origin.dy, 92);
      expect(tester.getSize(text).height, 20);
      final decoration = tester.widget<DecoratedBox>(panel).decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFFFFFFF));
      expect(decoration.border, Border.all(color: const Color(0xFFE9E9E9)));
      expect(decoration.borderRadius, BorderRadius.circular(12));
      final style = tester.widget<Text>(text).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, const Color(0xFF222222)));
      expect(tester.widget<Text>(text).textAlign, TextAlign.center);
    });
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다. 숫자 칸·빈 상태 판 둘 다 본다.
  final layouts = {'숫자 칸': summary, '빈 상태 판': summaryWith(delivered: 0, signups: 0, conversations: 0)};
  for (final MapEntry(key: layout, value: data) in layouts.entries) {
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('[$layout] pen 프레임 크기(360×884)·글자 배율 $scale 에서 어느 줄도 넘치지 않는다', (tester) async {
      // 테스트 글꼴은 한글이 Pretendard 보다 넓다 — 여기서 버티면 실제 폰에서도 버틴다.
      tester.view.physicalSize = const Size(360, 884);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester, Success(data));
      await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('[$layout] 글자 배율 2.0 에서 본문 글자가 고정 상자에 잘리지 않는다', (tester) async {
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

    await pump(tester, Success(data));
    final clipped = clippedTexts();
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);
    clipped.addAll(clippedTexts());
    // 넘침은 위 배율 테스트가 본다 — 여기서는 잘림만 본다.
    tester.takeException();

    expect(clipped, isEmpty);
  });
  }

  testWidgets('pen 좌표와 같다 — hero 버튼 y146 · 숫자 칸 y423 높이 96 · 리뷰 y543 · 태그 y659 · 카드 y703 · 빈 칸 글자 x14', (tester) async {
    // pen `bpA8x` 값(앱바 56 포함). 글자 상자 높이 hero 29(`dIoz0`)·대학 제목 20(`YIoXQ`)은 렌더 결과(lineHeight 속성 없음), 빈 칸 글자 x14(`FqMYC`).
    tester.view.physicalSize = const Size(360, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester);

    final heroButton = find.ancestor(of: find.text('지금 확인하기'), matching: find.byType(InkWell));
    expect(tester.getTopLeft(heroButton).dy, 146);
    final tile = find.ancestor(of: find.text('전달된 카드'), matching: find.byType(Container)).first;
    expect(tester.getTopLeft(tile).dy, 423);
    expect(tester.getSize(tile).height, 96);
    final review = find.ancestor(of: find.text('리뷰 남기기'), matching: find.byType(Container)).last;
    expect(tester.getTopLeft(review).dy, 543);
    expect(tester.getTopLeft(find.byType(Tag).first).dy, 659);
    final nudge = find.ancestor(of: find.text('프로필을 조금 더 채우면'), matching: find.byType(Container)).last;
    expect(tester.getTopLeft(nudge).dy, 703);
    final emptyTile = tester.getTopLeft(find.byType(MosaicEmptyTile).first);
    expect(tester.getTopLeft(find.text('아직 비어 있어요').first).dx - emptyTile.dx, 14);
  });

  testWidgets('review-strip `L7wKi` — 바탕 #FFF8EC, 별은 3D 15 다섯 개(`hN4Ow` 외)', (tester) async {
    penFrame(tester);
    await pump(tester);

    final strip = find.ancestor(of: find.text('리뷰 남기기'), matching: find.byType(Container)).last;
    expect((tester.widget<Container>(strip).decoration! as BoxDecoration).color, const Color(0xFFFFF8EC));
    final stars = find.descendant(of: strip, matching: find.byType(Icon3d));
    expect(tester.widgetList<Icon3d>(stars).map((i) => (i.icon, i.size)), List.filled(5, (AppIcon3d.star, 15.0)));
  });

  testWidgets('hero `U1k8ZK` — 바탕 #FFF0F2 · 하트 장식 없음 · 마스코트 `S49nUs` x172 y-5 160×170 · 제목 #222 · 버튼 `t0Un8s` #FF385C 글자 흰색', (tester) async {
    penFrame(tester);
    await pump(tester);

    final title = find.text('오늘의 카드가');
    final hero = find.ancestor(of: title, matching: find.byType(Container)).last;
    expect((tester.widget<Container>(hero).decoration! as BoxDecoration).color, const Color(0xFFFFF0F2));
    expect(find.descendant(of: hero, matching: find.byIcon(AppIcons.heart)), findsNothing);
    final mascot = find.descendant(of: hero, matching: find.byType(Image));
    expect((tester.widget<Image>(mascot).image as AssetImage).assetName, 'assets/images/home-top-mascot-couple.webp');
    expect(tester.getRect(mascot).shift(-tester.getTopLeft(hero)), const Rect.fromLTWH(172, -5, 160, 170));
    expect(tester.widget<Text>(title).style!.color, const Color(0xFF222222));
    final button = find.ancestor(of: find.text('지금 확인하기'), matching: find.byType(Material)).first;
    expect(tester.widget<Material>(button).color, const Color(0xFFFF385C));
    expect(tester.widget<Text>(find.text('지금 확인하기')).style!.color, const Color(0xFFFFFFFF));
  });

  testWidgets('stat-panel `krua8` — 칸 바탕 3색 · 3D 아이콘 36 · 숫자 18/700 #222 · 라벨 11 #6A6A6A', (tester) async {
    await pump(tester);

    for (final (label, color, icon) in [
      ('전달된 카드', const Color(0xFFFFF6F8), AppIcon3d.send),
      ('가입 수', const Color(0xFFF8F5FF), AppIcon3d.join),
      ('시작된 대화', const Color(0xFFF5F7FF), AppIcon3d.chat),
    ]) {
      final tile = find.ancestor(of: find.text(label), matching: find.byType(Container)).first;
      final box = tester.widget<Container>(tile).decoration! as BoxDecoration;
      expect((box.color, box.borderRadius), (color, BorderRadius.circular(14)), reason: label);
      final icon3d = tester.widget<Icon3d>(find.descendant(of: tile, matching: find.byType(Icon3d)));
      expect((icon3d.icon, icon3d.size), (icon, 36.0), reason: label);
      final labelStyle = tester.widget<Text>(find.text(label)).style!;
      expect((labelStyle.fontSize, labelStyle.color), (11, const Color(0xFF6A6A6A)), reason: label);
    }
    final number = tester.widget<Text>(find.text('862')).style!;
    expect((number.fontSize, number.fontWeight, number.color), (18, FontWeight.w700, const Color(0xFF222222)));
  });

  testWidgets('완성도 막대 `v8D23` — 흰 바탕 · 테두리 #D8C8D9 40 · 그림자 y1 blur4 #745C78 1C', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

    final bar = find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 150 && w.constraints?.maxHeight == 6);
    final box = tester.widget<Container>(bar).decoration! as BoxDecoration;
    expect(box.color, const Color(0xFFFFFFFF));
    // 테두리는 위에 그린다 — decoration 테두리는 Container 가 안쪽 여백으로 더해 채움 막대가 4 로 준다.
    expect((tester.widget<Container>(bar).foregroundDecoration! as BoxDecoration).border, Border.all(color: const Color(0x40D8C8D9)));
    expect(box.boxShadow, const [BoxShadow(color: Color(0x1C745C78), offset: Offset(0, 1), blurRadius: 4)]);
  });

  testWidgets('요약을 못 받아도 hero-today 는 남는다', (tester) async {
    await pump(tester, const FailureResult(NetworkFailure()));

    expect(find.text('지금 확인하기'), findsOneWidget);
    expect(find.text('전달된 카드'), findsNothing);
    // 코호트인지 모르니 대기 화면도 없다 — 카드로 가는 길이 남는 쪽이 맞다(계획서 Review Focus 3).
    expect(find.byType(CohortWaitView), findsNothing);
  });

  group('19 코호트 — 메인 탭 안에서 바꿔 끼운다(계획서 결정 1)', () {
    testWidgets('cohort 가 있으면 대기 화면이 있고 09b 는 없다. 앱바 · 하단 내비는 그대로', (tester) async {
      await pump(
        tester,
        Success(HomeSummary(
          presentPeopleImages: summary.presentPeopleImages,
          deliveredCards: summary.deliveredCards,
          signups: summary.signups,
          conversationsStarted: summary.conversationsStarted,
          reviewRating: summary.reviewRating,
          reviewCount: summary.reviewCount,
          campuses: summary.campuses,
          profileCompletionPercent: summary.profileCompletionPercent,
          cohort: CohortWait(firstCardAt: DateTime.now().add(const Duration(days: 3)), recruitCount: 5),
        )),
      );

      expect(find.byType(CohortWaitView), findsOneWidget);
      expect(find.text('지금 확인하기'), findsNothing);
      expect(find.text('전달된 카드'), findsNothing);
      expect(find.text('CampusMate'), findsOneWidget);
      expect(find.byType(NotifyIconButton), findsOneWidget);
      expect(find.byType(AppBottomNav), findsOneWidget);
    });

    testWidgets('cohort 가 null 이면 09b 그대로다', (tester) async {
      await pump(tester);

      expect(find.byType(CohortWaitView), findsNothing);
      expect(find.text('지금 확인하기'), findsOneWidget);
    });
  });
}
