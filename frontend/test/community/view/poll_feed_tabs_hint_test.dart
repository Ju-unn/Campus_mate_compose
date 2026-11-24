import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/view/poll_feed_tabs.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 19-3 탭 줄 안내 움직임(pen 25-F1 `MUBW9` · `RXFHp`, 사용자 결정 11-25 「a 로 하는데 너무 빠르면 안돼」):
/// 커뮤니티에 들어올 때마다 0.4초 뒤 왕복 4초로 끝까지 갔다가 돌아온다 · 손이 닿으면 그 자리에 멈춘다 ·
/// 동작 줄이기 · 투어 중 · 밀 것 없음이면 안 움직인다.
void main() {
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    String? account = 'profile-a',
    double width = 360,
    bool reduceMotion = false,
    bool tourActive = false,
    ValueChanged<CommunityFeedTab>? onSelected,
  }) async {
    tester.view.physicalSize = Size(width, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: [
      tourAccountIdProvider.overrideWithValue(() => account),
    ]);
    addTearDown(container.dispose);
    if (tourActive) container.read(appTourViewModelProvider.notifier).replay();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: Scaffold(
              appBar: AppBar(
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(PollFeedTabs.heightFor(MediaQuery.textScalerOf(context))),
                  child: PollFeedTabs(selected: CommunityFeedTab.all, onSelected: onSelected ?? (_) {}),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(PollFeedTabs), matching: find.byType(Scrollable)))
      .position
      .pixels;

  /// 화면을 내린다 — 다음 진입은 새 탭 줄이다(커뮤니티 탭은 이동마다 새로 만들어진다).
  Future<void> leave(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  const half = Duration(milliseconds: 2000);

  testWidgets('진입: 0.4초 뒤 시작해 2초에 끝(200)까지 갔다가 다시 2초에 처음 자리로 — 왕복 4초', (tester) async {
    await pump(tester);

    await tester.pump(const Duration(milliseconds: 399));
    expect(offset(tester), 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(half);
    expect(offset(tester), 200);
    await tester.pump(half);
    expect(offset(tester), 0);
    expect(PollFeedTabs.hintRoundTrip, const Duration(seconds: 4));
  });

  testWidgets('가기 절반 지점(1초)은 floatCurve(easeInOut) 자리다 — 일정한 속도가 아니다', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));

    expect(offset(tester), moreOrLessEquals(200 * Curves.easeInOut.transform(500 / 2000), epsilon: 0.01));
  });

  testWidgets('움직이는 중에 탭을 누르면 그 탭이 눌린다(멈춤이 누름을 막지 않는다)', (tester) async {
    final picked = <CommunityFeedTab>[];
    await pump(tester, onSelected: picked.add);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(PollFeedTabs.tabKey(CommunityFeedTab.popular)));
    await tester.pump();

    expect(picked, [CommunityFeedTab.popular]);
  });

  testWidgets('끄개(E2E 하네스가 끔)가 꺼져 있으면 움직이지 않는다', (tester) async {
    PollFeedTabs.hintEnabled = false;
    addTearDown(() => PollFeedTabs.hintEnabled = true);
    await pump(tester);
    await tester.pump(const Duration(seconds: 5));

    expect(offset(tester), 0);
  });

  testWidgets('들어올 때마다 움직인다 — 4번째 · 5번째 진입에도', (tester) async {
    final moved = <bool>[];
    for (var visit = 0; visit < 5; visit++) {
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(half);
      moved.add(offset(tester) == 200);
      await tester.pump(half);
      await leave(tester);
    }

    expect(moved, [true, true, true, true, true]);
  });

  testWidgets('움직이는 중 손이 닿으면 그 자리에 멈추고 되돌아가지 않는다', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    final stoppedAt = offset(tester);
    expect(stoppedAt, inExclusiveRange(0, 200));

    final finger = await tester.startGesture(tester.getCenter(find.byType(PollFeedTabs)));
    await tester.pump();
    await finger.up();
    await tester.pump(const Duration(seconds: 5));

    expect(offset(tester), stoppedAt);
  });

  testWidgets('시작 전에 손이 닿으면 움직이지 않는다', (tester) async {
    await pump(tester);
    final finger = await tester.startGesture(tester.getCenter(find.byType(PollFeedTabs)));
    await tester.pump(const Duration(milliseconds: 100));
    await finger.up();
    await tester.pump(const Duration(seconds: 5));

    expect(offset(tester), 0);
  });

  testWidgets('동작 줄이기면 움직이지 않는다', (tester) async {
    await pump(tester, reduceMotion: true);
    await tester.pump(const Duration(seconds: 5));

    expect(offset(tester), 0);
  });

  testWidgets('탭이 화면에 다 들어가 밀 것이 없으면(넓은 화면) 움직이지 않는다', (tester) async {
    await pump(tester, width: 800);
    await tester.pump(const Duration(seconds: 5));

    expect(offset(tester), 0);
  });

  testWidgets('앱 투어가 떠 있는 동안(3단계가 탭 줄을 가리킴)엔 움직이지 않는다', (tester) async {
    await pump(tester, tourActive: true);
    await tester.pump(const Duration(seconds: 5));

    expect(offset(tester), 0);
  });

  testWidgets('계정을 모르면(로그인 전 · 시험) 움직이지 않는다', (tester) async {
    await pump(tester, account: null);
    await tester.pump(const Duration(seconds: 5));

    expect(offset(tester), 0);
  });

  testWidgets('시작 전 · 움직이는 중에 화면을 떠나도 타이머 · 움직임이 남지 않는다', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await leave(tester);

    await pump(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    await leave(tester);
    await tester.pumpAndSettle();
  });
}
