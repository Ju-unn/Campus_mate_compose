import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/view/poll_composer_screen.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/view/vote_option.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_community_repository.dart';

void main() {
  late FakeCommunityRepository repository;

  setUp(() => repository = FakeCommunityRepository());

  Future<void> pump(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/community',
      routes: [
        GoRoute(path: '/community', builder: (context, state) => const Text('피드')),
        GoRoute(path: '/community/new', builder: (context, state) => const PollComposerScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [communityRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/community/new');
    await tester.pumpAndSettle();
  }

  ElevatedButton submit(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '익명으로 올리기'));

  /// pen 화면 폭 360 × 780 — 칸 폭(164 · 158 · 328)은 이 폭에서 잰다.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 17b 직접 적기 탭(pen `Xe28J`)을 연다 — 기본은 O/X 탭이다.
  Future<void> openCustom(WidgetTester tester) async {
    await tester.tap(find.text('직접 적기'));
    await tester.pumpAndSettle();
  }

  const oxGuide = 'O = 찬성, X = 반대로 투표를 받아요';
  const customGuide = '보기 글자는 1~6자, 서로 달라야 해요';

  Color? fillOf(WidgetTester tester, Finder option) {
    final box = tester.widget<DecoratedBox>(find.descendant(of: option, matching: find.byType(DecoratedBox)).first);
    return (box.decoration as BoxDecoration).color;
  }

  testWidgets('O/X 탭(기본): 질문만 있으면 올리기가 켜지고 "찬성"/"반대"로 보낸다', (tester) async {
    await pump(tester);
    expect(submit(tester).onPressed, isNull);

    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '깻잎을 먼저 집으면 안 되나?');
    await tester.pump();
    expect(submit(tester).onPressed, isNotNull);

    await tester.tap(find.text('익명으로 올리기'));
    await tester.pumpAndSettle();
    expect(repository.created.single, (question: '깻잎을 먼저 집으면 안 되나?', optionA: '찬성', optionB: '반대'));
  });

  testWidgets('직접 적기 탭: 보기 둘이 비었거나 같으면 올리기가 꺼져 있다', (tester) async {
    await pump(tester);
    await openCustom(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '짜장 vs 짬뽕');
    await tester.pump();
    expect(submit(tester).onPressed, isNull); // 보기가 비어 있다

    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '짜장');
    await tester.enterText(find.byKey(PollComposerScreen.optionBKey), '짬뽕');
    await tester.pump();
    expect(submit(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(PollComposerScreen.optionBKey), '짜장');
    await tester.pump();
    expect(submit(tester).onPressed, isNull);
  });

  testWidgets('탭 2칸(O/X · 직접 적기): 찬성/반대 탭은 없다, 폭 164 · 높이 44, 선택은 #C4224B 700 + 밑줄 2', (tester) async {
    phone(tester);
    await pump(tester);
    expect(find.text('찬성/반대'), findsNothing);
    final ox = tester.getRect(find.byKey(PollComposerScreen.oxTabKey));
    final custom = tester.getRect(find.byKey(PollComposerScreen.customTabKey));
    expect((ox.size, custom.size), (const Size(164, 44), const Size(164, 44)));
    expect(ox.left, 16);
    expect(custom.left, ox.right);

    TextStyle style(String label) => tester.widget<Text>(find.text(label)).style!;
    expect((style('O/X').color, style('O/X').fontWeight, style('O/X').fontSize), (AppColors.primaryText, FontWeight.w700, 14.0));
    expect((style('직접 적기').color, style('직접 적기').fontWeight), (AppColors.muted, FontWeight.w500));
    ColoredBox underline(Key key) => tester.widget<ColoredBox>(find.byKey(key));
    expect(underline(PollComposerScreen.oxUnderlineKey).color, AppColors.primaryText);
    expect(tester.getSize(find.byKey(PollComposerScreen.oxUnderlineKey)).height, 2);
    expect(underline(PollComposerScreen.customUnderlineKey).color, Colors.transparent);

    await openCustom(tester);
    expect(style('직접 적기').color, AppColors.primaryText);
    expect(style('직접 적기').fontWeight, FontWeight.w700);
    expect(style('O/X').color, AppColors.muted);
    expect(underline(PollComposerScreen.customUnderlineKey).color, AppColors.primaryText);
    expect(underline(PollComposerScreen.oxUnderlineKey).color, Colors.transparent);
  });

  testWidgets('탭의 눌림 효과는 화면이 아니라 탭 칸에 그려진다(COMMON §4-2)', (tester) async {
    // InkWell 은 가장 가까운 Material 에 칠한다 — 그게 Scaffold 면 효과가 화면 전체(360 × 780)에 번진다.
    phone(tester);
    await pump(tester);
    for (final label in ['O/X', '직접 적기']) {
      final tab = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      final painter = find.ancestor(of: find.text(label), matching: find.byType(Material)).first;
      expect(tester.getSize(painter), tester.getSize(tab), reason: label);
    }
  });

  testWidgets('O/X 탭: 파랑 O 칸 · 빨강 X 칸(158 × 72, 칸 사이 12)과 안내 글, 입력칸은 없다(tKjGJ)', (tester) async {
    phone(tester);
    await pump(tester);
    expect(find.text('투표 방식'), findsOneWidget);
    final options = find.byType(VoteOption);
    expect(options, findsNWidgets(2));
    expect(find.byIcon(AppIcons.circle), findsOneWidget);
    expect(find.byIcon(AppIcons.x), findsOneWidget);
    expect(find.byKey(PollComposerScreen.optionAKey), findsNothing);
    final blue = tester.getRect(options.at(0));
    final red = tester.getRect(options.at(1));
    expect((blue.size, red.size), (const Size(158, 72), const Size(158, 72)));
    expect(red.left - blue.right, 12);
    expect(fillOf(tester, options.at(0)), pollAgreeBlue);
    expect(fillOf(tester, options.at(1)), AppColors.primary);
    expect(find.text(oxGuide), findsOneWidget);
    expect(find.text(customGuide), findsNothing);
    expect(tester.widget<Text>(find.text(oxGuide)).style!.color, AppColors.muted);
  });

  testWidgets('직접 적기 탭: 파랑·빨강 입력 칸 둘과 안내 글(Xe28J), 회색 상자는 없다', (tester) async {
    phone(tester);
    await pump(tester);
    await openCustom(tester);
    final options = find.byType(VoteOption);
    expect(options, findsNWidgets(2));
    expect(find.byKey(PollComposerScreen.optionAKey), findsOneWidget);
    expect(find.byKey(PollComposerScreen.optionBKey), findsOneWidget);
    expect(find.text('보기 1'), findsOneWidget);
    expect(find.text('보기 2'), findsOneWidget);
    expect(find.text(customGuide), findsOneWidget);
    expect(find.text(oxGuide), findsNothing);
    expect(find.text('선택지 A'), findsNothing);
    expect(fillOf(tester, options.at(0)), pollAgreeBlue);
    expect(fillOf(tester, options.at(1)), AppColors.primary);
    expect(tester.getSize(options.at(0)), const Size(158, 72));
  });

  testWidgets('O/X 탭에서 올리면 직접 적기 탭에 적던 글자는 무시하고 찬성/반대로 보낸다', (tester) async {
    await pump(tester);
    await openCustom(tester);
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '짜장');
    await tester.tap(find.text('O/X'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '뭐 먹지?');
    await tester.pump();
    await tester.tap(find.text('익명으로 올리기'));
    await tester.pumpAndSettle();
    expect(repository.created.single, (question: '뭐 먹지?', optionA: '찬성', optionB: '반대'));
  });

  testWidgets('탭을 오가도 직접 적던 보기는 그대로 남는다', (tester) async {
    await pump(tester);
    await openCustom(tester);
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '짜장');
    await tester.tap(find.text('O/X'));
    await tester.pumpAndSettle();
    await openCustom(tester);
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.optionAKey)).controller!.text, '짜장');
  });

  testWidgets('카운터는 상자 안에서 "n / 80"', (tester) async {
    await pump(tester);
    expect(find.text('0 / 80'), findsOneWidget);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '짜장');
    await tester.pump();
    expect(find.text('2 / 80'), findsOneWidget);
  });

  testWidgets('앞뒤 공백을 깎아 보내고 피드로 돌아가 새로 읽는다', (tester) async {
    await pump(tester);
    await openCustom(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '  짜장 vs 짬뽕  ');
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), ' 짜장 ');
    await tester.enterText(find.byKey(PollComposerScreen.optionBKey), '짬뽕');
    await tester.pump();
    await tester.tap(find.text('익명으로 올리기'));
    await tester.pumpAndSettle();

    expect(repository.created.single, (question: '짜장 vs 짬뽕', optionA: '짜장', optionB: '짬뽕'));
    expect(find.text('피드'), findsOneWidget);
    expect(repository.pageRequests, isNotEmpty);
  });

  testWidgets('올리는 중(17b UqasS): 버튼이 꺼지고 스피너는 없다', (tester) async {
    repository.holdCreate = Completer<void>();
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '짜장 vs 짬뽕');
    await tester.pump();
    await tester.tap(find.text('익명으로 올리기'));
    await tester.pump();
    expect(submit(tester).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    repository.holdCreate!.complete();
    await tester.pumpAndSettle();
    expect(repository.created.length, 1);
    expect(find.text('피드'), findsOneWidget);
  });

  testWidgets('하루 10개를 넘기면(429) 한도 문구를 보이고 화면에 남는다', (tester) async {
    repository.createResult = const FailureResult(RateLimitedFailure());
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '열한 번째');
    await tester.pump();
    await tester.tap(find.text('익명으로 올리기'));
    await tester.pumpAndSettle();

    expect(find.text(pollDailyLimitMessage), findsOneWidget);
    expect(find.text('피드'), findsNothing);

    // pen 17b 올리기 실패 `u4UOb`: 오류 글 error 색, 안내 글 아래 20 · 버튼 위 8, 버튼은 다시 켜진다.
    // 글 높이는 보지 않는다 — bodySmall lh1.55(21.7)와 pen 렌더 23 이 다르다(줄높이 있는 글은 토큰을 따른다).
    final error = find.text(pollDailyLimitMessage);
    expect(tester.widget<Text>(error).style!.color, AppColors.error);
    final guide = tester.getRect(find.text(oxGuide));
    final errorRect = tester.getRect(error);
    final button = tester.getRect(find.widgetWithText(ElevatedButton, '익명으로 올리기'));
    expect(errorRect.top - guide.bottom, 20);
    expect(button.top - errorRect.bottom, 8);
    expect(submit(tester).onPressed, isNotNull);
    expect(button.height, 52); // HE8FZ 2026-10-01 개편
  });

  testWidgets('입력칸은 80자 · 6자에서 더 받지 않는다', (tester) async {
    await pump(tester);
    await openCustom(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '가' * 90);
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '가' * 15);
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.questionKey)).controller!.text.length, 80);
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.optionAKey)).controller!.text.length, 6);
  });

  testWidgets('글자 수는 서버와 같이 코드 포인트로 센다(이모지 👍🏻 = 2)', (tester) async {
    await pump(tester);
    await openCustom(tester);
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '👍🏻' * 4);
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.optionAKey)).controller!.text.runes.length, 6);
  });

  testWidgets('폰 폭(360)에서 글자 2배 · 80자 질문에도 넘치거나 잘리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '가' * 80);
    await tester.pump();

    // 넘침 오류는 Flex 만 낸다 — 고정 상자에 갇힌 글자(라벨 · 카운터 · 안내 · 버튼)는 오류 없이 잘린다.
    List<String> clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
          p.text.toPlainText(),
    ];
    expect(tester.takeException(), isNull);
    final clipped = clippedTexts();
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    clipped.addAll(clippedTexts());

    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await openCustom(tester);
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '가나다라마바');
    await tester.enterText(find.byKey(PollComposerScreen.optionBKey), '사아자차카타');
    await tester.pump();
    expect(tester.takeException(), isNull);
    clipped.addAll(clippedTexts());
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    clipped.addAll(clippedTexts());
    // 보기 안내 글("보기 1" · "보기 2")은 글자를 적으면 투명해진다. 테스트 글꼴(Ahem)은 글자가 모두 정사각형이라 실제보다 넓게 나온다.
    clipped.removeWhere((text) => text.startsWith('보기 '));
    expect(clipped, isEmpty);
  });

  testWidgets('pen 앱바: 뒤로 arrow-left 22 · 제목 x60(jrUTh · g58njs · RKulj)', (tester) async {
    await pump(tester);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft)).size, 22);
    expect(tester.getCenter(find.byIcon(AppIcons.arrowLeft)).dx, 8 + 24);
    expect(tester.getTopLeft(find.text('익명으로 질문하기')).dx, 60);
  });

  testWidgets('pen 본문: 안쪽 16 · 덩어리 사이 20, 질문 상자 100 · 카운터는 상자 아래 안쪽 12(QhlmU · Zhq9p · tKjGJ)', (tester) async {
    phone(tester);
    await pump(tester);
    final notice = tester.getRect(find.ancestor(of: find.byIcon(AppIcons.lock), matching: find.byType(Container)).first);
    final label = tester.getRect(find.text('질문 내용'));
    final box = tester.getRect(
      find.ancestor(of: find.byKey(PollComposerScreen.questionKey), matching: find.byType(Container)).first,
    );
    final counter = tester.getRect(find.text('0 / 80'));
    final voteLabel = tester.getRect(find.text('투표 방식'));
    final tabs = tester.getRect(find.byKey(PollComposerScreen.modeTabsKey));
    final options = find.byType(VoteOption);
    final guide = tester.getRect(find.text('O = 찬성, X = 반대로 투표를 받아요'));
    final button = tester.getRect(find.widgetWithText(ElevatedButton, '익명으로 올리기'));

    expect(notice.top, 56 + 16);
    expect(notice.left, 16);
    expect(label.top - notice.bottom, 20);
    expect(label.height, 20); // `BxeOU/VCwQo` 14/600, 줄 높이 속성 없음 · 렌더 20
    expect(box.top - label.bottom, 8); // TextInput 라벨~상자 8
    expect(box.height, 100); // 17b 질문 상자 100(대장 10-08, 옛 104)
    // 테두리 1 + 안쪽 12(Container 는 테두리 두께를 안쪽 여백에 더한다).
    expect(box.bottom - counter.bottom, 12 + 1);
    expect(counter.left - box.left, 12 + 1);
    // VoteSection: 세로 간격 12 — 라벨 → 3칸이 아니라 2칸 탭 → 보기 줄 → 안내 글.
    expect(voteLabel.top - box.bottom, 20);
    expect(voteLabel.height, 20); // 14/600, 줄 높이 속성 없음 · 렌더 20
    expect(tabs.top - voteLabel.bottom, 12);
    expect(tabs.size, const Size(328, 44));
    expect(tester.getTopLeft(options.at(0)).dy - tabs.bottom, 12);
    expect(tester.getSize(options.at(0)).height, 72);
    expect(guide.top - tester.getBottomLeft(options.at(0)).dy, 12);
    expect(guide.height, 18); // 12 · 줄 높이 1.5
    expect(button.top - guide.bottom, 20);
    expect(button.height, 52); // HE8FZ 2026-10-01 개편
  });
}
