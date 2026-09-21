import 'dart:convert';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [CardRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류와 세션 확인은
/// 조각 1b 의 [sendAuthorizedRequest] 가 이미 하므로 여기서는 URL·바디·파싱만 맡는다.
class HttpCardRepository implements CardRepository {
  const HttpCardRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  Future<Result<T>> _send<T>(
    String method,
    String path,
    T Function(Object body) parse, {
    Map<String, Object?>? body,
  }) async {
    final result = await sendAuthorizedRequest(_client, _auth, (accessToken) {
      final request = http.Request(method, Uri.parse('$_baseUrl$path'))
        ..headers['Authorization'] = 'Bearer $accessToken';
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body);
      }
      return request;
    });
    return result.when(
      onSuccess: (response) => Success(parse(jsonDecode(response.body))),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  @override
  Future<Result<TodayCards>> fetchToday() =>
      _send('GET', '/cards/today', (body) => TodayCards.fromJson(body as Map<String, dynamic>));

  @override
  Future<Result<CardDetail>> fetchCard(String cardId) =>
      _send('GET', '/cards/$cardId', (body) => CardDetail.fromJson(body as Map<String, dynamic>));

  @override
  Future<Result<void>> decide(String cardId, CardDecision decision) => _send(
        'POST',
        '/cards/$cardId/decision',
        (_) {},
        body: {'decision': decision.wire},
      );

  @override
  Future<Result<List<Acceptance>>> fetchAcceptances() => _send(
        'GET',
        '/cards/acceptances',
        (body) => ((body as Map<String, dynamic>)['acceptances'] as List<dynamic>)
            .map((item) => Acceptance.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  @override
  Future<Result<AcceptanceOutcome>> respondToAcceptance(String cardId, CardDecision decision) =>
      _send(
        'POST',
        '/cards/acceptances/$cardId',
        (body) => AcceptanceOutcome.fromJson(body as Map<String, dynamic>),
        body: {'decision': decision.wire},
      );

  @override
  Future<Result<void>> registerPushToken(String token) =>
      _send('POST', '/cards/push-tokens', (_) {}, body: {'token': token, 'platform': 'android'});

  @override
  Future<Result<void>> deletePushToken(String token) =>
      _send('DELETE', '/cards/push-tokens/$token', (_) {});

  @override
  Future<Result<NotificationPreferences>> fetchNotificationPreferences() => _send(
        'GET',
        '/cards/notification-settings',
        (body) => NotificationPreferences.fromJson(body as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> updateNotificationPreference(String key, bool value) =>
      _send('PATCH', '/cards/notification-settings', (_) {}, body: {key: value});

  @override
  Future<Result<void>> setMatchingPaused(bool paused) =>
      _send('PATCH', '/cards/matching-paused', (_) {}, body: {'paused': paused});
}
