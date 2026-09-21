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

  int fetchTodayCount = 0;
  final List<({String cardId, CardDecision decision})> decisions = [];
  final List<({String key, bool value})> preferenceUpdates = [];
  final List<String> registeredTokens = [];
  final List<String> deletedTokens = [];
  bool? pausedValue;

  @override
  Future<Result<TodayCards>> fetchToday() async {
    fetchTodayCount += 1;
    return today;
  }

  @override
  Future<Result<CardDetail>> fetchCard(String cardId) async => card!;

  @override
  Future<Result<void>> decide(String cardId, CardDecision decision) async {
    decisions.add((cardId: cardId, decision: decision));
    return writeResult;
  }

  @override
  Future<Result<List<Acceptance>>> fetchAcceptances() async => acceptances;

  @override
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision) async {
    decisions.add((cardId: cardId, decision: decision));
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
  Future<Result<void>> setMatchingPaused(bool paused) async {
    pausedValue = paused;
    return writeResult;
  }
}
