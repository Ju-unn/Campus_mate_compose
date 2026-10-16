import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';
import 'package:campus_mate/matching/model/sent_request.dart';

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
  /// 결제 카드를 연다(하트 차감 포함). 성공하면 새 카드 번호다. 402 · 409 는 [PaidPurchaseFailure] 로 가른다.
  Future<Result<String>> purchasePaidCard(String offerId);
  Future<Result<void>> decide(String cardId, CardDecision decision);
  Future<Result<List<Acceptance>>> fetchAcceptances();

  /// 받은 신청 한 건의 상대 프로필(pen `o4QqYR`) — 10b 와 같은 몸통이고 실사진 · 카카오톡 아이디는 없다.
  /// 남의 것 · 숨김 · 이미 매칭 404, 이미 답함 409, 7일 지남 410 은 서버 문구 그대로 실패로 온다.
  Future<Result<CardDetail>> fetchAcceptanceDetail(String cardId);
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision);

  /// 내가 대화 신청한 카드들(대화 탭 "보낸 신청"). 최신 신청 먼저, 최대 50건 — 서버 순서 그대로다.
  Future<Result<List<SentRequest>>> fetchSentRequests();
  Future<Result<void>> registerPushToken(String token);
  Future<Result<void>> deletePushToken(String token);
  Future<Result<NotificationPreferences>> fetchNotificationPreferences();
  Future<Result<void>> updateNotificationPreference(String key, bool value);
  Future<Result<bool>> fetchMatchingPaused();
  Future<Result<void>> setMatchingPaused(bool paused);
}
