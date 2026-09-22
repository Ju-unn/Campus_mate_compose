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
  Future<Result<void>> registerPushToken(String token) {
    final platform = _devicePlatform();
    if (platform == null) {
      // 웹·데스크톱에는 등록할 자리가 없다(`device_platform` enum 이 android·ios 둘뿐이다).
      // 보낼 것이 없을 뿐 실패한 것은 아니라서 성공으로 돌려준다.
      return Future.value(const Success(null));
    }
    // device_platform enum 에는 ios 도 있다 — 'android' 를 박아 두면 아이폰 토큰까지
    // android 로 들어가서, 나중에 기기별로 손댈 때 구분할 근거가 사라진다.
    return _api.send('POST', '/cards/push-tokens', (_) {},
        body: {'token': token, 'platform': platform});
  }

  /// dart:io 의 `Platform` 대신 [defaultTargetPlatform] 을 보는 건 테스트에서 덮어쓸 수 있어서다.
  /// 다만 그 값은 **웹·데스크톱에서 android 로 떨어진다** — `kIsWeb` 을 먼저 보고,
  /// 모르는 플랫폼이면 android 로 뭉뚱그리지 않고 null 을 돌려준다(조각 4 리뷰 권고 5번).
  String? _devicePlatform() {
    if (kIsWeb) {
      return null;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

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
