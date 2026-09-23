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
  interests: const ['등산'],
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
