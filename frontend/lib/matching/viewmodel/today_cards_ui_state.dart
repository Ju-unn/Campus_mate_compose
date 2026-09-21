import 'package:campus_mate/matching/model/daily_card.dart';

/// 오늘 탭이 그릴 수 있는 다섯 모양. 화면은 이 값 하나로 갈린다.
enum TodayCardsPhase {
  /// 첫 조회 중 — `Skeleton · Card` 2장(화면 `Ukg21`)
  loading,

  /// 받은 카드가 있다(화면 `W0CjO`·`eDPkz`)
  cards,

  /// 오늘 몫은 끝났고 다음 지급일을 기다린다(화면 `i4VFS`)
  waiting,

  /// 후보 풀 자체가 비었다(화면 `iQZoa`)
  noCandidates,

  /// 조회 실패 — 다시 시도 버튼
  failed,
}

class TodayCardsUiState {
  const TodayCardsUiState({
    this.phase = TodayCardsPhase.loading,
    this.cards = const [],
    this.nextIssueAt,
    this.errorMessage,
  });

  final TodayCardsPhase phase;
  final List<DailyCard> cards;
  final DateTime? nextIssueAt;
  final String? errorMessage;
}
