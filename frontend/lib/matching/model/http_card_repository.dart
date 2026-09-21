import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';
import 'package:flutter/foundation.dart';

/// [CardRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류와 세션 확인은
/// 조각 1b 의 `sendAuthorizedRequest` 가 이미 하므로 여기서는 URL·바디·파싱만 맡는다.
class HttpCardRepository implements CardRepository {
  const HttpCardRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<TodayCards>> fetchToday() => _api.send(
      'GET', '/cards/today', (body) => TodayCards.fromJson(body as Map<String, dynamic>));

  @override
  Future<Result<CardDetail>> fetchCard(String cardId) => _api.send(
      'GET', '/cards/$cardId', (body) => CardDetail.fromJson(body as Map<String, dynamic>));

  @override
  Future<Result<void>> decide(String cardId, CardDecision decision) => _api.send(
        'POST',
        '/cards/$cardId/decision',
        (_) {},
        body: {'decision': decision.wire},
      );

  @override
  Future<Result<List<Acceptance>>> fetchAcceptances() => _api.send(
        'GET',
        '/cards/acceptances',
        (body) => ((body as Map<String, dynamic>)['acceptances'] as List<dynamic>)
            .map((item) => Acceptance.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  @override
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision) =>
      _api.send(
        'POST',
        '/cards/acceptances/$cardId',
        (body) => AcceptanceOutcome.fromJson(body as Map<String, dynamic>),
        body: {'decision': decision.wire},
      );

  @override
  Future<Result<void>> registerPushToken(String token) => _api.send(
        'POST',
        '/cards/push-tokens',
        (_) {},
        // device_platform enum 에는 ios 도 있다 — 'android' 를 박아 두면 아이폰 토큰까지
        // android 로 들어가서, 나중에 기기별로 손댈 때 구분할 근거가 사라진다.
        // dart:io 의 Platform 대신 defaultTargetPlatform 을 보는 건 테스트에서 덮어쓸 수 있어서다.
        body: {
          'token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        },
      );

  @override
  Future<Result<void>> deletePushToken(String token) =>
      _api.send('DELETE', '/cards/push-tokens/$token', (_) {});

  @override
  Future<Result<NotificationPreferences>> fetchNotificationPreferences() => _api.send(
        'GET',
        '/cards/notification-settings',
        (body) => NotificationPreferences.fromJson(body as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> updateNotificationPreference(String key, bool value) =>
      _api.send('PATCH', '/cards/notification-settings', (_) {}, body: {key: value});

  @override
  Future<Result<void>> setMatchingPaused(bool paused) =>
      _api.send('PATCH', '/cards/matching-paused', (_) {}, body: {'paused': paused});
}
