import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

const _profile = CardProfile(profileId: 't1', nickname: '여우비', age: 23);
const _card = DailyCard(cardId: 'card-1', source: CardSource.daily, profile: _profile);

void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository();
    container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  Future<TodayCardsUiState> load() async {
    await container.read(todayCardsViewModelProvider.notifier).refresh();
    return container.read(todayCardsViewModelProvider);
  }

  test('카드가 있으면 카드 상태가 된다', () async {
    repository.today = const Success(TodayCards(cards: [_card]));

    final state = await load();

    expect(state.phase, TodayCardsPhase.cards);
    expect(state.cards.single.cardId, 'card-1');
  });

  test('카드가 없고 다음 지급일이 있으면 대기 상태다 (화면 11)', () async {
    repository.today = Success(TodayCards(cards: const [], nextIssueAt: DateTime(2026, 9, 24, 7)));

    final state = await load();

    expect(state.phase, TodayCardsPhase.waiting);
  });

  test('후보 풀이 비었으면 대기가 아니라 "소개할 사람 없음"이다 (화면 11b)', () async {
    repository.today = Success(
      TodayCards(cards: const [], nextIssueAt: DateTime(2026, 9, 24, 7), candidatePoolEmpty: true),
    );

    final state = await load();

    expect(state.phase, TodayCardsPhase.noCandidates);
  });

  test('실패하면 오류 문구를 들고 실패 상태가 된다', () async {
    repository.today = const FailureResult(NetworkFailure());

    final state = await load();

    expect(state.phase, TodayCardsPhase.failed);
    expect(state.errorMessage, const NetworkFailure().toDisplayMessage());
  });

  test('결정하면 목록을 다시 읽는다 — 카드가 사라진 화면을 남기지 않는다', () async {
    repository.today = const Success(TodayCards(cards: [_card]));
    await load();

    await container.read(todayCardsViewModelProvider.notifier).markDecided();

    expect(repository.fetchTodayCount, 2);
  });
}
