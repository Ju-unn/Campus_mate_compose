import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/trait_bar.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../model/fake_card_repository.dart';

final _detail = CardDetail(
  cardId: 'card-1',
  profile: const CardProfile(
    profileId: 't1',
    nickname: '여우비',
    age: 23,
    university: '테스트대학교',
    major: '컴퓨터공학과',
  ),
  survey: List.filled(9, 0.5),
  animalType: AnimalType.cat,
  impressionType: ImpressionType.chic,
  religion: Religion.none,
  isSmoker: false,
  interests: const ['등산', '영화'],
  myTraits: const ['유머러스'],
  idealTraits: const ['다정한'],
  mbti: 'ENFP',
  studentNumber: '20',
);

void main() {
  Future<FakeCardRepository> pump(WidgetTester tester) async {
    final repository = FakeCardRepository()..card = Success(_detail);
    final container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        // 10b 도 "오늘" 탭 하단 내비를 달고 있어 뱃지가 안 읽은 메시지 수를 읽는다(§8.8).
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CardDetailScreen(cardId: 'card-1')),
      ),
    );
    await tester.pump();
    return repository;
  }

  testWidgets('이름·성향 9축·수락 거절 버튼을 보여준다', (tester) async {
    await pump(tester);

    expect(find.text('여우비, 23'), findsOneWidget);
    expect(find.text('ENFP'), findsOneWidget);
    expect(find.byType(TraitBar), findsNWidgets(9));
    expect(find.text('거절'), findsOneWidget);
    expect(find.text('수락하기'), findsOneWidget);
  });

  testWidgets('태그 칩은 줄 폭을 먹지 않아 같은 줄에 나란히 선다', (tester) async {
    // 실기기에서 태그가 한 줄에 하나씩 세로로 쌓였다(백로그 24). `Container(alignment:)` 는 폭 제한이
    // 없으면 `Wrap` 이 준 최대 폭을 통째로 먹는다 — 칩은 글자 폭만큼만 차지해야 한다.
    await pump(tester);

    final first = tester.getTopLeft(find.text('등산'));
    final second = tester.getTopLeft(find.text('영화'));
    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
  });

  testWidgets('"오늘" 탭 하단 내비를 달고 앱바에 톱니가 없다', (tester) async {
    // 카드를 열어도 오늘 탭 안이다. 설정으로 가는 길은 "나" 탭 하나로 모았다(2026-09-23 사용자 결정).
    await pump(tester);

    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(find.byIcon(AppIcons.settings), findsNothing);
  });

  testWidgets('학교·학과·학번은 이름 밑 한 줄이고 사실 칸에 학과가 없다', (tester) async {
    // 2026-09-23 pen `TORAs` 대조 — 학과가 두 군데 나오던 것을 학교 줄 하나로 모았다.
    await pump(tester);

    expect(find.text('테스트대학교 컴퓨터공학과 20학번'), findsOneWidget);
    expect(find.text('학과'), findsNothing);
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다(백로그 31).
  void setScreen(WidgetTester tester, double scale) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('글자 배율 $scale 에서 어느 줄도 넘치지 않는다', (tester) async {
      // 테스트 글꼴은 한글이 Pretendard 보다 넓다 — 여기서 버티면 실제 폰에서도 버틴다.
      setScreen(tester, scale);

      await pump(tester);
      await tester.scrollUntilVisible(find.text('수락하기'), 200);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('배율 1.0 에서는 pen 대로 칩 높이 30 · 사실 칸 3열 2줄이다', (tester) async {
    // pen `TORAs` 칩 `H7jmhR` 높이 30, 사실 칸 `unvGU`·`c5wYv`·`Mm1Xn` 3열(열 사이 8)·줄 사이 10.
    // 최소 크기로 바꾼 뒤에도 기본 배율 모양은 그대로여야 한다.
    setScreen(tester, 1.0);
    await pump(tester);

    final chip = find.ancestor(
      of: find.text('등산'),
      matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.minHeight == 30),
    );
    expect(tester.getSize(chip).height, 30);
    final height = tester.getTopLeft(find.text('키'));
    final mbti = tester.getTopLeft(find.text('MBTI'));
    final studentNumber = tester.getTopLeft(find.text('학번'));
    final religion = tester.getTopLeft(find.text('종교'));
    expect(mbti.dy, height.dy);
    expect(studentNumber.dy, height.dy);
    expect(mbti.dx - height.dx, studentNumber.dx - mbti.dx);
    expect(religion.dx, height.dx);
    expect(religion.dy, greaterThan(height.dy));
  });

  testWidgets('글자 배율 2.0 에서 화면 어느 글자도 고정 상자에 잘리지 않는다', (tester) async {
    // 넘침 오류는 Flex 만 낸다 — SizedBox·Container 높이·폭에 갇힌 글자는 오류 없이 잘린다.
    setScreen(tester, 2.0);

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
    await tester.scrollUntilVisible(find.text('수락하기'), 200);
    clipped.addAll(clippedTexts());
    // 넘침은 위 배율 테스트가 본다 — 여기서는 잘림만 본다.
    tester.takeException();

    expect(clipped.toSet(), isEmpty);
  });

  testWidgets('수락을 누르면 수락이 서버로 간다', (tester) async {
    final repository = await pump(tester);

    // 버튼이 하단 고정에서 카드 아래로 내려와(pen `TORAs`) 스크롤해야 닿는다.
    await tester.ensureVisible(find.text('수락하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수락하기'));
    await tester.pump();

    expect(repository.decisions.single.decision, CardDecision.accept);
  });
}
