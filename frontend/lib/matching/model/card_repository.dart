import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';

/// 수락·거절 한 쌍. 카드 결정과 수락함 응답이 같은 값을 쓴다(ERD `card_decision`).
enum CardDecision {
  accept,
  reject;

  String get wire => name;
}

/// 조각 4 가 쓰는 서버 호출 전부. 화면은 이 인터페이스만 보고 `Http…` 구현을 모른다.
abstract interface class CardRepository {
  Future<Result<TodayCards>> fetchToday();
  Future<Result<CardDetail>> fetchCard(String cardId);
  Future<Result<void>> decide(String cardId, CardDecision decision);
  Future<Result<List<Acceptance>>> fetchAcceptances();
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision);
  Future<Result<void>> registerPushToken(String token);
  Future<Result<void>> deletePushToken(String token);
  Future<Result<NotificationPreferences>> fetchNotificationPreferences();
  Future<Result<void>> updateNotificationPreference(String key, bool value);
  Future<Result<void>> setMatchingPaused(bool paused);
}
