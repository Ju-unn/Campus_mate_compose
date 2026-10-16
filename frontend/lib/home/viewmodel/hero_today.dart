import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 홈 hero-today 가 그릴 모양. 오늘 탭이 이미 읽은 상태를 그대로 쓴다 — 홈이 따로 조회하지 않는다.
final heroTodayProvider = Provider<HeroToday>((ref) => HeroToday.from(ref.watch(todayCardsViewModelProvider)));

/// hero-today 모양(DESIGN §8.9 · pen `U1k8ZK` 도착 · `fxlhV` 결정 대기 · `HGxAR` 확인 완료 · `VdvmY` 불러오는 중).
sealed class HeroToday {
  const HeroToday();

  /// 무료 카드가 있으면 도착(산 카드가 같이 있어도 오늘 카드 소식이 먼저다), 산 카드만 남았으면 결정 대기,
  /// 오늘 몫을 다 정했으면 확인 완료, 처음 읽는 동안은 불러오는 중(다시 읽을 때는 앞 상태를 그대로 둔다 — 오늘 탭이 loading 으로
  /// 돌아가지 않는다).
  /// ponytail: 실패 · 후보가 빈 11b 는 pen 에 hero 모양이 없어 지금까지의 문구(도착)로 둔다 — "지금 확인하기"를 누르면 오늘 탭이
  /// 실패 · 11b 화면을 보인다. pen 에 실패 · 11b hero 가 그려지면 여기서 갈라 준다.
  factory HeroToday.from(TodayCardsUiState state) => switch (state.phase) {
        TodayCardsPhase.cards when state.cards.any((card) => card.source == CardSource.daily) => const HeroArrived(),
        TodayCardsPhase.cards => HeroPending(state.cards.length),
        TodayCardsPhase.waiting => HeroDone(state.nextIssueAt),
        TodayCardsPhase.loading => const HeroLoading(),
        TodayCardsPhase.failed || TodayCardsPhase.noCandidates => const HeroArrived(),
      };
}

/// ⓪ 오늘 카드를 읽는 중 — 문구 · 버튼 자리에 정적 스켈레톤 막대(pen `VdvmY` 의 hero `jHiXf`)
final class HeroLoading extends HeroToday {
  const HeroLoading();
}

/// ① 오늘의 카드가 도착했어요 · 지금 확인하기
final class HeroArrived extends HeroToday {
  const HeroArrived();
}

/// ② 결정 대기 카드가 [count]장 남아 있어요 · 이어서 확인하기 + 우상단 장수 배지
final class HeroPending extends HeroToday {
  const HeroPending(this.count);

  final int count;
}

/// ③ 오늘 카드는 모두 확인했어요 · 다음 카드까지 카운트다운(시각을 모르면 카운트다운 없이)
final class HeroDone extends HeroToday {
  const HeroDone(this.nextIssueAt);

  final DateTime? nextIssueAt;
}
