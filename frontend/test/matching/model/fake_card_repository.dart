import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';

/// 화면·ViewModel 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeCardRepository implements CardRepository {
  FakeCardRepository({this.onDelete});

  /// 토큰 삭제가 일어난 "시점"을 보고 싶을 때만 쓴다(로그아웃 순서 테스트).
  final void Function()? onDelete;

  Result<TodayCards> today = const Success(TodayCards(cards: []));
  Result<CardDetail>? card;
  Result<List<Acceptance>> acceptances = const Success([]);
  Result<AcceptanceOutcome> acceptanceOutcome = const Success(AcceptanceOutcome(matched: false));
  Result<void> writeResult = const Success(null);
  Result<NotificationPreferences> preferences = const Success(NotificationPreferences());
  Result<bool> paused = const Success(false);

  int fetchTodayCount = 0;

  /// 유료 카드 구매 결과. 성공이면 새 카드 번호다.
  Result<String> purchaseResult = const Success('card-new');

  /// 구매가 서버에 간 제안 번호들(몇 번 갔는지 · 어느 제안인지).
  final List<String> purchasedOfferIds = [];

  /// 채워 두면 구매 응답이 이것이 끝날 때까지 멈춘다 — 응답 도중에 또 누르는 상황용.
  Completer<void>? holdPurchase;

  /// 채워 두면 구매 호출이 끝난 뒤의 [fetchToday] 는 이 값을 돌려준다(서버가 산 카드를 목록에 넣은 모양).
  Result<TodayCards>? todayAfterPurchase;

  /// 수락함을 읽은 횟수. 앱 복귀·화면 진입 때 다시 읽는지 볼 때 쓴다.
  int fetchAcceptancesCount = 0;

  /// 채워 두면 수락 응답이 이것이 끝날 때까지 멈춘다 — 응답 도중에 목록을 다시 읽는 상황용.
  Completer<void>? holdRespond;

  /// 채워 두면 수락함 조회가 이것이 끝날 때까지 멈춘다 — 읽는 도중에 또 읽으려는 상황용.
  Completer<void>? holdAcceptances;
  final List<({String cardId, CardDecision decision})> decisions = [];
  final List<({String key, bool value})> preferenceUpdates = [];
  final List<String> registeredTokens = [];
  final List<String> deletedTokens = [];
  bool? pausedValue;

  @override
  Future<Result<TodayCards>> fetchToday() async {
    fetchTodayCount += 1;
    return purchasedOfferIds.isNotEmpty && todayAfterPurchase != null ? todayAfterPurchase! : today;
  }

  @override
  Future<Result<String>> purchasePaidCard(String offerId) async {
    purchasedOfferIds.add(offerId);
    await holdPurchase?.future;
    return purchaseResult;
  }

  @override
  Future<Result<CardDetail>> fetchCard(String cardId) async => card!;

  @override
  Future<Result<void>> decide(String cardId, CardDecision decision) async {
    decisions.add((cardId: cardId, decision: decision));
    return writeResult;
  }

  @override
  Future<Result<List<Acceptance>>> fetchAcceptances() async {
    fetchAcceptancesCount += 1;
    // 요청한 시점의 값을 들고 있다가 멈춘 뒤 돌려준다 — 서버가 요청 때 본 목록을 늦게 받는 모양.
    final snapshot = acceptances;
    await holdAcceptances?.future;
    return snapshot;
  }

  @override
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision) async {
    decisions.add((cardId: cardId, decision: decision));
    await holdRespond?.future;
    return acceptanceOutcome;
  }

  @override
  Future<Result<void>> registerPushToken(String token) async {
    registeredTokens.add(token);
    return writeResult;
  }

  @override
  Future<Result<void>> deletePushToken(String token) async {
    deletedTokens.add(token);
    onDelete?.call();
    return writeResult;
  }

  @override
  Future<Result<NotificationPreferences>> fetchNotificationPreferences() async => preferences;

  @override
  Future<Result<void>> updateNotificationPreference(String key, bool value) async {
    preferenceUpdates.add((key: key, value: value));
    return writeResult;
  }

  @override
  Future<Result<bool>> fetchMatchingPaused() async => paused;

  @override
  Future<Result<void>> setMatchingPaused(bool paused) async {
    pausedValue = paused;
    return writeResult;
  }
}
