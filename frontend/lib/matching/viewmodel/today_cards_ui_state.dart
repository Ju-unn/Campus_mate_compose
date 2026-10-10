import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/paid_card.dart';

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

/// 결제 카드를 열다가 화면이 한 번 알려 줘야 하는 일(지시문 23 D). 화면이 읽어 가면 비운다.
enum PurchaseNoticeKind {
  /// 402 — 하트 부족 시트 → 하트 스토어
  heartsNotEnough,

  /// 409 — 화면은 이미 새로 읽었다. 안내 토스트만 남았다
  offerGone,

  /// 그 밖의 실패 — 토스트
  failed,
}

class PurchaseNotice {
  const PurchaseNotice(this.kind, [this.message]);

  final PurchaseNoticeKind kind;

  /// 토스트에 쓸 문구([PurchaseNoticeKind.heartsNotEnough] 는 시트라 없다).
  final String? message;
}

class TodayCardsUiState {
  const TodayCardsUiState({
    this.phase = TodayCardsPhase.loading,
    this.cards = const [],
    this.nextIssueAt,
    this.errorMessage,
    this.paidCard,
    this.isPurchasing = false,
    this.notice,
  });

  final TodayCardsPhase phase;
  final List<DailyCard> cards;
  final DateTime? nextIssueAt;
  final String? errorMessage;

  /// 결제 카드 자리(카드 목록 · 대기 화면 아래에 **추가로** 그린다). 없으면 null.
  final PaidCard? paidCard;

  /// 열기 요청이 가 있는 동안 true — 버튼을 잠가 두 번 눌림을 막는다.
  final bool isPurchasing;
  final PurchaseNotice? notice;

  /// [notice] 는 덮어쓰기다(null 을 주면 지운다) — 나머지는 안 주면 그대로다.
  TodayCardsUiState copyWith({bool? isPurchasing, PurchaseNotice? notice}) {
    return TodayCardsUiState(
      phase: phase,
      cards: cards,
      nextIssueAt: nextIssueAt,
      errorMessage: errorMessage,
      paidCard: paidCard,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      notice: notice,
    );
  }
}
