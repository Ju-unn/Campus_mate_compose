import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

const _acceptance = Acceptance(
  cardId: 'card-1',
  profile: CardProfile(
    profileId: 'p1',
    nickname: '초코라떼',
    age: 25,
    university: '고려대학교',
    major: '경영학과',
  ),
);

void main() {
  Future<void> pump(WidgetTester tester, FakeCardRepository repository) async {
    final container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConversationsScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('수락 대기 섹션에 사람 수와 행을 보여준다', (tester) async {
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);

    await pump(tester, repository);

    expect(find.text('수락 대기'), findsOneWidget);
    expect(find.text('1명'), findsOneWidget);
    expect(find.text('초코라떼, 25'), findsOneWidget);
    expect(find.text('수락하고 대화 시작'), findsOneWidget);
  });

  testWidgets('받은 수락이 없으면 빈 상태 문구만 보여준다', (tester) async {
    await pump(tester, FakeCardRepository());

    expect(find.text('아직 시작된 대화가 없어요'), findsOneWidget);
    expect(find.text('수락 대기'), findsNothing);
  });

  testWidgets('거절을 누르면 거절이 서버로 간다', (tester) async {
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);
    await pump(tester, repository);

    await tester.tap(find.text('거절'));
    await tester.pump();

    expect(repository.decisions.single.decision, CardDecision.reject);
  });
}
