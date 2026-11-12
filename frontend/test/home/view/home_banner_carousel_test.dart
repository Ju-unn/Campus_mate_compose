import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/home/model/data/home_summary.dart';
import 'package:campus_mate/home/view/home_banner_carousel.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// pen 컴포넌트 HomeSeasonCarousel `z4q4nv`(홈 v3 `kkKiZ`, 11-12) — 세로: 그림 328×184 모서리 16 → 10 → 점 줄
/// CarouselDots · 5 `djKOY`(지름 6 · 사이 6 · 현재 #222222 · 나머지 #DDDDDD). 3초마다 다음 장, 마지막 다음은 처음.
/// 그림은 기기 캐시(CachedNetworkImage)로 받는다 — 시험에는 기기 캐시가 없어 오는 중으로 멈춰 있고, 그동안 회색 바탕이 보인다.
void main() {
  const three = [
    HomeBanner(imageUrl: 'https://cdn.test/a.webp', altText: '크리스마스에 어디 가세요?'),
    HomeBanner(imageUrl: 'https://cdn.test/b.webp', altText: '곧 1월 1일이에요'),
    HomeBanner(imageUrl: 'https://cdn.test/c.webp', altText: '연말 모임에 같이 갈 사람 찾기'),
  ];

  Future<void> pump(
    WidgetTester tester,
    List<HomeBanner> banners, {
    double width = 328,
    bool disableAnimations = false,
    bool accessibleNavigation = false,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: HomeBannerCarousel(banners: banners)),
            ),
          ),
        ),
      ),
    );
  }

  double page(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView)).controller!.page!;

  /// 3초를 흘리고 넘김 움직임(220ms)이 끝날 때까지 기다린다.
  Future<void> wait3s(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder dots() => find.byWidgetPredicate(
        (w) => w is Container && w.constraints == const BoxConstraints.tightFor(width: 6, height: 6),
      );

  testWidgets('0장이면 아무것도 그리지 않는다(칸 높이 0)', (tester) async {
    await pump(tester, const []);

    expect(find.byType(PageView), findsNothing);
    expect(tester.getSize(find.byType(HomeBannerCarousel)).height, 0);
  });

  testWidgets('그림 칸 328×184 · 모서리 16 · 회색 바탕(오는 중 · 실패 때 보인다), 그림은 덮어 그린다', (tester) async {
    await pump(tester, three);

    final frame = find.ancestor(of: find.byType(CachedNetworkImage).first, matching: find.byType(Container)).first;
    expect(tester.getSize(frame), const Size(328, 184));
    final box = tester.widget<Container>(frame).decoration! as BoxDecoration;
    expect((box.color, box.borderRadius), (AppColors.surfaceSoft, BorderRadius.circular(16)));
    expect(tester.widget<Container>(frame).clipBehavior, Clip.antiAlias);
    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage).first);
    expect((image.imageUrl, image.fit), ('https://cdn.test/a.webp', BoxFit.cover));
  });

  testWidgets('그림을 못 받으면 아무것도 덧그리지 않아 회색 바탕만 남는다', (tester) async {
    await pump(tester, three);

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage).first);
    final failed = image.errorWidget!(tester.element(find.byType(CachedNetworkImage).first), image.imageUrl, Exception('x'));
    expect(failed, isA<SizedBox>());
  });

  testWidgets('폭이 넓으면 비율(328:184)을 지키며 늘어난다', (tester) async {
    await pump(tester, three, width: 368);

    expect(tester.getSize(find.byType(PageView)), const Size(368, 368 * 184 / 328));
  });

  testWidgets('여러 장 — 그림 아래 10 에 점 줄: 장 수만큼 지름 6 · 사이 6 · 가운데, 현재 ink · 나머지 hairline', (tester) async {
    await pump(tester, three);

    expect(dots(), findsNWidgets(3));
    final rects = [for (var i = 0; i < 3; i++) tester.getRect(dots().at(i))];
    expect(rects.first.top - tester.getRect(find.byType(PageView)).bottom, 10);
    expect(rects[1].left - rects[0].right, 6);
    expect(rects[2].left - rects[1].right, 6);
    expect((rects.first.left + rects.last.right) / 2, 328 / 2);
    expect(tester.getSize(find.byType(HomeBannerCarousel)), const Size(328, 184 + 10 + 6));
    Color colorOf(int i) => (tester.widget<Container>(dots().at(i)).decoration! as BoxDecoration).color!;
    expect([colorOf(0), colorOf(1), colorOf(2)], [AppColors.ink, AppColors.hairline, AppColors.hairline]);
  });

  testWidgets('1장이면 점이 없고 넘기지 않는다', (tester) async {
    await pump(tester, three.sublist(0, 1));

    expect(dots(), findsNothing);
    expect(tester.getSize(find.byType(HomeBannerCarousel)), const Size(328, 184));
    await wait3s(tester);
    await wait3s(tester);
    expect(page(tester), 0);
  });

  testWidgets('3초마다 다음 장으로 넘기고 점도 따라간다 — 마지막 다음은 처음', (tester) async {
    await pump(tester, three);

    await tester.pump(const Duration(milliseconds: 2900));
    expect(page(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(page(tester), 1);
    expect((tester.widget<Container>(dots().at(1)).decoration! as BoxDecoration).color, AppColors.ink);
    await wait3s(tester);
    expect(page(tester), 2);
    await wait3s(tester);
    expect(page(tester), 0);
  });

  testWidgets('기기 "동작 줄이기" 면 저절로 넘기지 않는다', (tester) async {
    await pump(tester, three, disableAnimations: true);

    await wait3s(tester);
    await wait3s(tester);
    expect(page(tester), 0);
  });

  testWidgets('화면 읽기가 켜져 있으면 저절로 넘기지 않는다', (tester) async {
    await pump(tester, three, accessibleNavigation: true);

    await wait3s(tester);
    await wait3s(tester);
    expect(page(tester), 0);
  });

  testWidgets('홈이 가려지면(TickerMode 꺼짐 — 다른 탭 · 위에 쌓인 화면) 저절로 넘기지 않고, 다시 보이면 이어 넘긴다', (tester) async {
    Future<void> pumpTicker(bool enabled) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TickerMode(
            enabled: enabled,
            child: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 328, child: HomeBannerCarousel(banners: three)),
              ),
            ),
          ),
        ),
      );
    }

    await pumpTicker(false);
    await wait3s(tester);
    await wait3s(tester);
    expect(page(tester), 0);
    // 멈춘 Ticker 에 넘김 움직임이 걸려 있지도 않다(타이머 자체가 멈췄다).
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.position.isScrollingNotifier.value, isFalse);

    // 가려진 동안 넘김을 쌓아 두지 않는다 — 다시 보이자마자 넘어가지 않고 그때부터 3초 뒤에 넘긴다.
    await pumpTicker(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(page(tester), 0);
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 400));
    expect(page(tester), 1);
  });

  testWidgets('앱이 뒤로 가 있는 동안은 넘기지 않고, 돌아오면 그때부터 3초 뒤에 넘긴다', (tester) async {
    await pump(tester, three);
    // 기기와 같은 순서로 지난다(resumed → inactive → hidden → paused, 돌아올 때는 거꾸로).
    void walk(List<AppLifecycleState> states) {
      for (final state in states) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    walk(const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
    await tester.pump(const Duration(seconds: 7));
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.position.isScrollingNotifier.value, isFalse);

    walk(const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(page(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(page(tester), 1);
  });

  testWidgets('누르고 있는 동안 멈추고, 떼면 3초 뒤 다시 넘긴다', (tester) async {
    await pump(tester, three);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PageView)));
    await wait3s(tester);
    await wait3s(tester);
    expect(page(tester), 0);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(page(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(page(tester), 1);
  });

  testWidgets('배너가 바뀌어 줄면 화면을 벗어나지 않고 넘김도 이어 간다', (tester) async {
    await pump(tester, three);
    await wait3s(tester);
    await wait3s(tester);
    expect(page(tester), 2);

    await pump(tester, three.sublist(0, 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(dots(), findsNWidgets(2));
    await wait3s(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('낭독기 — 그림마다 그림 속 문구를 그림으로 읽고, 누르기 동작은 없다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, three);

    final data = tester.getSemantics(find.bySemanticsLabel('크리스마스에 어디 가세요?')).getSemanticsData();
    expect(data.flagsCollection.isImage, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector).evaluate().where((e) => (e.widget as GestureDetector).onTap != null), isEmpty);
    handle.dispose();
  });
}
