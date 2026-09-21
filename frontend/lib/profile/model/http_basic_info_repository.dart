import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/profile/model/basic_info_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [BasicInfoRepository]를 FastAPI 호출로 구현한다.
class HttpBasicInfoRepository implements BasicInfoRepository {
  const HttpBasicInfoRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<bool>> checkNicknameAvailability(String nickname) async {
    final uri = Uri.parse('$_baseUrl/profile-onboarding/nickname-availability')
        .replace(queryParameters: {'nickname': nickname});
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $accessToken',
    );
    return result.when(
      onSuccess: (response) => Success((jsonDecode(response.body) as Map<String, dynamic>)['available'] as bool),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  @override
  Future<Result<void>> submit(BasicInfoSubmission submission) async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/basic-info'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
      'nickname': submission.nickname,
      'birth_year': submission.birthYear,
      'height_cm': submission.heightCm,
      'phone_number': submission.phoneNumber,
      'gender': submission.gender,
      'mbti': submission.mbti,
      }),
    );
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
