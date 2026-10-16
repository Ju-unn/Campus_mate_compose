import 'package:campus_mate/home/viewmodel/hero_today.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// hero-today 세 모양(pen `U1k8ZK` 도착 · `fxlhV` 결정 대기 · `HGxAR` 확인 완료)을 오늘 탭 상태에서 고른다.
void main() {
  const profile = CardProfile(profileId: 'p', nickname: '여우비', age: 23, university: '가람대', major: '경영학과');
  const free = DailyCard(cardId: 'free', source: CardSource.daily, profile: profile);
  const bought = DailyCard(cardId: 'paid-1', source: CardSource.purchased, profile: profile);
  const bought2 = DailyCard(cardId: 'paid-2', source: CardSource.purchased, profile: profile);
  final next = DateTime(2026, 10, 15, 7);

  test('무료 카드가 있으면 도착 — 산 카드가 같이 있어도 도착이 먼저다', () {
    const state = TodayCardsUiState(phase: TodayCardsPhase.cards, cards: [free, bought]);

    expect(HeroToday.from(state), isA<HeroArrived>());
  });

  test('산 카드만 남아 있으면 결정 대기 N장', () {
    const state = TodayCardsUiState(phase: TodayCardsPhase.cards, cards: [bought, bought2]);

    expect(HeroToday.from(state), isA<HeroPending>().having((h) => h.count, 'count', 2));
  });

  test('오늘 몫을 다 정했으면 확인 완료 — 다음 지급 시각을 함께 들고 간다', () {
    final state = TodayCardsUiState(phase: TodayCardsPhase.waiting, nextIssueAt: next);

    expect(HeroToday.from(state), isA<HeroDone>().having((h) => h.nextIssueAt, 'nextIssueAt', next));
  });

  test('다음 지급 시각을 모르면 확인 완료지만 시각은 비어 있다', () {
    const state = TodayCardsUiState(phase: TodayCardsPhase.waiting);

    expect(HeroToday.from(state), isA<HeroDone>().having((h) => h.nextIssueAt, 'nextIssueAt', isNull));
  });

  test('처음 읽는 동안은 불러오는 중 — 도착 문구를 먼저 보이지 않는다(pen `VdvmY` 스켈레톤)', () {
    expect(HeroToday.from(const TodayCardsUiState()), isA<HeroLoading>());
  });

  // 실패 · 후보가 빈 11b 는 pen 에 hero 모양이 없다 — 지금까지의 문구(도착)로 둔다.
  for (final phase in [TodayCardsPhase.failed, TodayCardsPhase.noCandidates]) {
    test('$phase 는 기존 문구(도착)로 둔다', () {
      expect(HeroToday.from(TodayCardsUiState(phase: phase)), isA<HeroArrived>());
    });
  }
}
