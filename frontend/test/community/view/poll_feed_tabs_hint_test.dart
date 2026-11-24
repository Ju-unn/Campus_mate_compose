import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/repository/community_tab_hint_store.dart';
import 'package:campus_mate/community/view/poll_feed_tabs.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_community_tab_hint_store.dart';

/// 19-3 탭 줄 안내 움직임(pen 25-F1 `MUBW9` · `RXFHp`, 대장 확정 11-24): 처음 3번 들어올 때만 0.4초 뒤
/// 왕복 2.5초로 끝까지 갔다가 돌아온다 · 손이 닿으면 그 자리에 멈춘다 · 동작 줄이기 · 투어 중 · 밀 것 없음이면 안 움직인다.
void main() {
  late FakeCommunityTabHintStore store;
  late ProviderContainer container;

  setUp(() => store = FakeCommunityTabHintStore());

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
      communityTabHintStoreProvider.overrideWithValue(store),
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

  const half = Duration(milliseconds: 1250);

  testWidgets('첫 진입: 0.4초 뒤 시작해 1.25초에 끝(200)까지 갔다가 다시 1.25초에 처음 자리로 — 1번 센다', (tester) async {
    await pump(tester);

    await tester.pump(const Duration(milliseconds: 399));
    expect(offset(tester), 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(half);
    expect(offset(tester), 200);
    await tester.pump(half);
    expect(offset(tester), 0);
    expect(store.played, {'profile-a': 1});
    expect(PollFeedTabs.hintRoundTrip, const Duration(milliseconds: 2500));
  });

  testWidgets('가기 절반 지점(0.625초)은 floatCurve(easeInOut) 자리다 — 일정한 속도가 아니다', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 312));

    expect(offset(tester), moreOrLessEquals(200 * Curves.easeInOut.transform(312 / 1250), epsilon: 0.01));
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

  testWidgets('끄개(E2E 하네스가 끔)가 꺼져 있으면 움직이지 않고 세지 않는다', (tester) async {
    PollFeedTabs.hintEnabled = false;
    addTearDown(() => PollFeedTabs.hintEnabled = true);
    await pump(tester);
    await tester.pump(const Duration(seconds: 3));

    expect(offset(tester), 0);
    expect(store.played, isEmpty);
  });

  testWidgets('1~3번째 진입에만 움직이고 4번째부터는 없다', (tester) async {
    final moved = <bool>[];
    for (var visit = 0; visit < 4; visit++) {
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(half);
      moved.add(offset(tester) > 0);
      await tester.pump(half);
      await leave(tester);
    }

    expect(moved, [true, true, true, false]);
    expect(store.played, {'profile-a': 3});
  });

  testWidgets('움직이는 중 손이 닿으면 그 자리에 멈추고 되돌아가지 않는다 — 그래도 1번 센다', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    final stoppedAt = offset(tester);
    expect(stoppedAt, inExclusiveRange(0, 200));

    final finger = await tester.startGesture(tester.getCenter(find.byType(PollFeedTabs)));
    await tester.pump();
    await finger.up();
    await tester.pump(const Duration(seconds: 3));

    expect(offset(tester), stoppedAt);
    expect(store.played, {'profile-a': 1});
  });

  testWidgets('시작 전에 손이 닿으면 움직이지 않고 세지 않는다', (tester) async {
    await pump(tester);
    final finger = await tester.startGesture(tester.getCenter(find.byType(PollFeedTabs)));
    await tester.pump(const Duration(milliseconds: 100));
    await finger.up();
    await tester.pump(const Duration(seconds: 3));

    expect(offset(tester), 0);
    expect(store.played, isEmpty);
  });

  testWidgets('동작 줄이기면 움직이지 않고 세지 않는다', (tester) async {
    await pump(tester, reduceMotion: true);
    await tester.pump(const Duration(seconds: 3));

    expect(offset(tester), 0);
    expect(store.played, isEmpty);
  });

  testWidgets('탭이 화면에 다 들어가 밀 것이 없으면(넓은 화면) 움직이지 않고 세지 않는다', (tester) async {
    await pump(tester, width: 800);
    await tester.pump(const Duration(seconds: 3));

    expect(offset(tester), 0);
    expect(store.played, isEmpty);
  });

  testWidgets('앱 투어가 떠 있는 동안(3단계가 탭 줄을 가리킴)엔 움직이지 않고 세지 않는다', (tester) async {
    await pump(tester, tourActive: true);
    await tester.pump(const Duration(seconds: 3));

    expect(offset(tester), 0);
    expect(store.played, isEmpty);
  });

  testWidgets('계정을 모르면(로그인 전 · 시험) 움직이지 않는다', (tester) async {
    await pump(tester, account: null);
    await tester.pump(const Duration(seconds: 3));

    expect(offset(tester), 0);
    expect(store.played, isEmpty);
  });

  testWidgets('로그아웃 뒤 다른 계정은 따로 센다 — 앞 계정이 3번 봤어도 처음처럼 움직인다', (tester) async {
    store.played['profile-a'] = 3;
    await pump(tester, account: 'profile-b');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(half);

    expect(offset(tester), 200);
    await tester.pump(half);
    expect(store.played, {'profile-a': 3, 'profile-b': 1});
  });

  testWidgets('저장소를 못 읽으면 움직이지 않는다', (tester) async {
    store = FakeCommunityTabHintStore(failing: true);
    await pump(tester);
    await tester.pump(const Duration(seconds: 3));

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
