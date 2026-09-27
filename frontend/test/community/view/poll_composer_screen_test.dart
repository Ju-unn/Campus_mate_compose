import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/view/poll_composer_screen.dart';
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

  testWidgets('질문이 비었거나 두 라벨이 같으면 올리기가 꺼져 있다', (tester) async {
    await pump(tester);
    expect(submit(tester).onPressed, isNull);

    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '짜장 vs 짬뽕');
    await tester.pump();
    expect(submit(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(PollComposerScreen.optionBKey), '찬성');
    await tester.pump();
    expect(submit(tester).onPressed, isNull);
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

  testWidgets('하루 10개를 넘기면(429) 한도 문구를 보이고 화면에 남는다', (tester) async {
    repository.createResult = const FailureResult(RateLimitedFailure());
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '열한 번째');
    await tester.pump();
    await tester.tap(find.text('익명으로 올리기'));
    await tester.pumpAndSettle();

    expect(find.text(pollDailyLimitMessage), findsOneWidget);
    expect(find.text('피드'), findsNothing);
  });

  testWidgets('입력칸은 80자 · 6자에서 더 받지 않는다', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(PollComposerScreen.questionKey), '가' * 90);
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '가' * 15);
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.questionKey)).controller!.text.length, 80);
    expect(tester.widget<TextField>(find.byKey(PollComposerScreen.optionAKey)).controller!.text.length, 6);
  });

  testWidgets('글자 수는 서버와 같이 코드 포인트로 센다(이모지 👍🏻 = 2)', (tester) async {
    await pump(tester);
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
    await tester.enterText(find.byKey(PollComposerScreen.optionAKey), '가나다라마바');
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
    expect(clipped, isEmpty);
  });

  testWidgets('pen 앱바: 뒤로 arrow-left 22 · 제목 x60(jrUTh · g58njs · RKulj)', (tester) async {
    await pump(tester);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft)).size, 22);
    expect(tester.getCenter(find.byIcon(AppIcons.arrowLeft)).dx, 8 + 24);
    expect(tester.getTopLeft(find.text('익명으로 질문하기')).dx, 60);
  });

  testWidgets('pen 본문: 안쪽 16 · 덩어리 사이 20, 질문 상자 104 · 카운터는 상자 아래 안쪽 12(QhlmU · Zhq9p)', (tester) async {
    await pump(tester);
    final notice = tester.getRect(find.ancestor(of: find.byIcon(AppIcons.lock), matching: find.byType(Container)).first);
    final label = tester.getRect(find.text('질문 내용'));
    final box = tester.getRect(
      find.ancestor(of: find.byKey(PollComposerScreen.questionKey), matching: find.byType(Container)).first,
    );
    final counter = tester.getRect(find.text('0 / 80'));
    final optionLabel = tester.getRect(find.text('선택지 A'));
    final button = tester.getRect(find.widgetWithText(ElevatedButton, '익명으로 올리기'));

    expect(notice.top, 56 + 16);
    expect(notice.left, 16);
    expect(label.top - notice.bottom, 20);
    expect(label.height, 20); // `BxeOU/VCwQo` 14/600, 줄 높이 속성 없음 · 렌더 20
    expect(box.top - label.bottom, 8); // TextInput 라벨~상자 8(BxeOU 렌더 128 = 20 + 8 + 100)
    expect(box.height, 104);
    // 테두리 1 + 안쪽 12(Container 는 테두리 두께를 안쪽 여백에 더한다).
    expect(box.bottom - counter.bottom, 12 + 1);
    expect(counter.left - box.left, 12 + 1);
    expect(optionLabel.top - box.bottom, 20);
    final optionBox = tester.getRect(
      find.ancestor(of: find.byKey(PollComposerScreen.optionAKey), matching: find.byType(Container)).first,
    );
    expect(optionBox.top - optionLabel.bottom, 6);
    expect(optionBox.height, 44);
    expect(button.top - optionBox.bottom, 20);
    expect(button.height, 56);
  });
}
