import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/trait_bar.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
);

void main() {
  Future<FakeCardRepository> pump(WidgetTester tester) async {
    final repository = FakeCardRepository()..card = Success(_detail);
    final container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
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
    expect(find.text('수락'), findsOneWidget);
  });

  testWidgets('수락을 누르면 수락이 서버로 간다', (tester) async {
    final repository = await pump(tester);

    await tester.tap(find.text('수락'));
    await tester.pump();

    expect(repository.decisions.single.decision, CardDecision.accept);
  });
}
